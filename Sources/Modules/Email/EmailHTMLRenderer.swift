import AppKit
import SwiftUI

/// Renders an email's HTML into an AttributedString the reader can show:
/// real paragraphs, bold/italic, working links — restyled for the dark
/// glass panel instead of the sender's white-background palette.
///
/// Privacy note: remote content never loads. Every <img> is stripped before
/// conversion, which kills tracking pixels along with pictures — a deliberate
/// trade for a mail client that runs on the desktop all day.
@MainActor
enum EmailHTMLRenderer {
    /// Conversion runs through AppKit's HTML importer (WebKit-backed, main
    /// thread only). Large newsletters take visible milliseconds — callers
    /// cache per message.
    static func render(_ html: String) -> NSAttributedString? {
        let cleaned = EmailHTMLSanitizer.strip(html)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let imported = try? NSMutableAttributedString(
            data: data, options: options, documentAttributes: nil
        ) else { return nil }
        restyle(imported)
        collapseBlankRuns(imported)
        return imported
    }

    /// Marketing HTML is padded with spacer rows and empty cells; imported
    /// verbatim they become screens of blank lines. Edited range by range,
    /// back to front — rebuilding the string would flatten every run and
    /// take the bold text and links with it.
    private static func collapseBlankRuns(_ text: NSMutableAttributedString) {
        guard let pattern = try? NSRegularExpression(pattern: "\n{3,}") else { return }
        let matches = pattern.matches(
            in: text.string,
            range: NSRange(location: 0, length: text.length)
        )
        for match in matches.reversed() {
            text.replaceCharacters(in: match.range, with: "\n\n")
        }
    }

    /// The sender styled for white paper; the widget is dark glass. Keep
    /// structure (weights, sizes relative to body, links) and replace the
    /// palette wholesale.
    private static func restyle(_ text: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: text.length)
        let bodyColor = NSColor.white.withAlphaComponent(0.88)
        let accent = NSColor(Theme.accent)

        text.enumerateAttributes(in: range) { attributes, subrange, _ in
            var updated = attributes
            updated[.backgroundColor] = nil
            updated[.foregroundColor] = attributes[.link] != nil ? accent : bodyColor
            if let font = attributes[.font] as? NSFont {
                updated[.font] = restyled(font)
            }
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle,
               let mutable = style.mutableCopy() as? NSMutableParagraphStyle {
                // Newsletter layouts assume 600pt canvases; the panel is a
                // third of that. Kill fixed indents so text uses the width.
                mutable.firstLineHeadIndent = 0
                mutable.headIndent = min(mutable.headIndent, 16)
                mutable.tailIndent = 0
                mutable.minimumLineHeight = 0
                mutable.maximumLineHeight = 0
                updated[.paragraphStyle] = mutable
            }
            text.setAttributes(updated, range: subrange)
        }
    }

    /// Maps the imported font onto the panel's type scale, preserving bold /
    /// italic / mono traits and keeping headings only relatively larger.
    private static func restyled(_ font: NSFont) -> NSFont {
        let traits = font.fontDescriptor.symbolicTraits
        let baseSize: CGFloat = 12.5
        // Headings arrive at 17–28pt on a 12pt body; compress the scale.
        let size = font.pointSize > 15 ? min(baseSize + (font.pointSize - 12) * 0.45, 17) : baseSize

        if traits.contains(.monoSpace) {
            return NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)
        }
        var weight: NSFont.Weight = .regular
        if traits.contains(.bold) { weight = .semibold }
        var restyled = NSFont.systemFont(ofSize: size, weight: weight)
        if traits.contains(.italic) {
            let descriptor = restyled.fontDescriptor.withSymbolicTraits(.italic)
            restyled = NSFont(descriptor: descriptor, size: size) ?? restyled
        }
        return restyled
    }
}
