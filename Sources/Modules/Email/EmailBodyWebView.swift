import AppKit
import SwiftUI
import WebKit

/// Renders an email body the way Mail.app does — in a real web engine.
/// AppKit's NSAttributedString HTML importer cannot lay out tables, keeps the
/// sender's white backgrounds and loses contrast; WebKit is what email HTML
/// is actually written for.
///
/// Privacy model, same as Mail's: by default nothing loads from the network —
/// a block-everything content rule stops tracking pixels, remote fonts and
/// images, so the sender cannot tell the mail was opened. `loadImages` is the
/// user's explicit per-message opt-in that lifts the block and shows images.
struct EmailBodyWebView: NSViewRepresentable {
    let html: String
    var loadImages = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // let the glass show through
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.load(html, loadImages: loadImages, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html, loadImages: loadImages, into: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loadedKey: String?
        /// Compiled once per launch; compiling is async, so the first body
        /// waits for it rather than risking an unguarded load.
        private static var blocker: WKContentRuleList?

        func load(_ html: String, loadImages: Bool, into webView: WKWebView) {
            let key = "\(loadImages)|\(html.hashValue)"
            guard loadedKey != key else { return }
            loadedKey = key
            let document = Self.document(from: html, loadImages: loadImages)
            Task {
                if loadImages {
                    webView.configuration.userContentController.removeAllContentRuleLists()
                } else if let blocker = await Self.networkBlocker() {
                    webView.configuration.userContentController.add(blocker)
                }
                // No base URL: relative references cannot resolve to anything.
                webView.loadHTMLString(document, baseURL: nil)
            }
        }

        /// Blocks every request the document makes. The body arrives inline,
        /// so nothing legitimate is lost.
        private static func networkBlocker() async -> WKContentRuleList? {
            if let blocker { return blocker }
            let rules = """
            [{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}]
            """
            let compiled = try? await WKContentRuleListStore.default()?
                .compileContentRuleList(forIdentifier: "hotz-mail-offline", encodedContentRuleList: rules)
            blocker = compiled
            return compiled
        }

        /// Clicks leave for the browser; nothing navigates in place.
        /// (The async form: the closure-based one no longer matches the
        /// protocol's @Sendable handler under Swift 6 and silently stops
        /// being a witness — links would then navigate inside the panel.)
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                // The initial loadHTMLString is `.other` — allow only that.
                return navigationAction.navigationType == .other ? .allow : .cancel
            }
            NSWorkspace.shared.open(url)
            return .cancel
        }

        private static func document(from html: String, loadImages: Bool) -> String {
            """
            <!doctype html><html><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>\(readerCSS)\(loadImages ? imagesCSS : noImagesCSS)</style></head>
            <body>\(EmailHTMLSanitizer.strip(html))</body></html>
            """
        }

        /// Reader styling: the sender's design is discarded on purpose. Their
        /// palette assumes white paper and a 600pt canvas; both are wrong
        /// here, and a half-adapted look is less readable than a clean one.
        ///
        /// `-webkit-text-fill-color` matters: newsletters pin colors with it
        /// precisely so mail clients' dark modes cannot recolor them — it
        /// overrides `color`, so it must be forced back to currentColor or
        /// headlines stay black on the dark glass.
        private static let readerCSS = """
        :root { color-scheme: dark; }
        html, body { margin: 0; padding: 0; background: transparent !important; }
        html { color: rgba(255,255,255,0.88) !important; }
        body {
          font-family: -apple-system, system-ui, sans-serif;
          font-size: 13px; line-height: 1.5;
          word-break: break-word; -webkit-text-size-adjust: 100%;
        }
        *, *::before, *::after {
          background-color: transparent !important;
          background-image: none !important;
          color: inherit !important;
          -webkit-text-fill-color: currentColor !important;
          border-color: rgba(255,255,255,0.10) !important;
          max-width: 100% !important;
          box-shadow: none !important;
        }
        /* Newsletters lay out in nested tables sized for a wide canvas —
           linearise them, and collapse the spacer cells they pad with. */
        table, tbody, tr, td, th {
          display: block !important; width: auto !important;
          height: auto !important; min-height: 0 !important;
          padding: 1px 0 !important;
        }
        a { color: \(accentCSS) !important; -webkit-text-fill-color: \(accentCSS) !important; text-decoration: underline; }
        h1, h2, h3, h4 { font-size: 15px; font-weight: 600; margin: 12px 0 6px; }
        p, div { margin: 0 0 6px; }
        hr { border: 0; border-top: 1px solid rgba(255,255,255,0.10); margin: 12px 0; }
        blockquote { margin: 8px 0; padding-left: 10px; border-left: 2px solid rgba(255,255,255,0.15); }
        video, iframe, svg, form, input, button { display: none !important; }
        """

        private static let noImagesCSS = """
        img, picture { display: none !important; }
        """

        private static let imagesCSS = """
        img, picture { max-width: 100% !important; height: auto !important; display: inline-block; }
        """

        private static var accentCSS: String {
            let color = NSColor(Theme.accent).usingColorSpace(.sRGB) ?? .green
            return String(
                format: "#%02X%02X%02X",
                Int(color.redComponent * 255),
                Int(color.greenComponent * 255),
                Int(color.blueComponent * 255)
            )
        }
    }
}
