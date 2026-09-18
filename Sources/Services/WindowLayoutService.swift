import AppKit
import ApplicationServices
import OSLog

/// Where a playbook puts its apps' windows once they are running.
enum WindowLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, leftRight, thirds, grid2x2, mainAndSide, fullscreen

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: "rectangle"
        case .leftRight: "rectangle.split.2x1"
        case .thirds: "rectangle.split.3x1"
        case .grid2x2: "rectangle.split.2x2"
        case .mainAndSide: "sidebar.left"
        case .fullscreen: "rectangle.inset.filled"
        }
    }

    @MainActor var title: String {
        switch self {
        case .none: L10n.t(.playLayoutNone)
        case .leftRight: L10n.t(.playLayoutLeftRight)
        case .thirds: L10n.t(.playLayoutThirds)
        case .grid2x2: L10n.t(.playLayoutGrid2x2)
        case .mainAndSide: L10n.t(.playLayoutMainSide)
        case .fullscreen: L10n.t(.playLayoutFullscreen)
        }
    }

    /// Slots as fractions of the screen's visible frame, in the unit square
    /// with a top-left origin and y growing downwards — the orientation
    /// Accessibility uses, so the flip from Cocoa happens once per screen.
    fileprivate var slots: [CGRect] {
        switch self {
        case .none:
            []
        case .leftRight:
            [
                CGRect(x: 0, y: 0, width: 0.5, height: 1),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            ]
        case .thirds:
            (0..<3).map { CGRect(x: CGFloat($0) / 3, y: 0, width: 1 / 3, height: 1) }
        case .grid2x2:
            [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]
        case .mainAndSide:
            [
                CGRect(x: 0, y: 0, width: 2 / 3, height: 1),
                CGRect(x: 2 / 3, y: 0, width: 1 / 3, height: 1),
            ]
        case .fullscreen:
            [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
    }
}

/// Moves other apps' windows through the Accessibility API — the only
/// sanctioned way to position a window that is not ours. Needs the user to
/// tick the app under Privacy & Security ▸ Accessibility; without that every
/// AX call fails with `.apiDisabled` and `arrange` is a no-op.
///
/// All AX calls run on the main actor: they are synchronous IPC round trips
/// in the low-millisecond range, and keeping the CF handles on one actor
/// spares us from pretending AXUIElement is Sendable.
@MainActor
final class WindowLayoutService {
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "playbooks")

    /// How long to wait for a freshly launched app to show a window.
    private static let windowWaitAttempts = 12
    private static let windowWaitInterval: Duration = .milliseconds(250)

    /// Whether the user granted Accessibility to this process.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system consent dialog and jumps to the Accessibility pane —
    /// the dialog alone only offers "Open System Settings", and users who
    /// dismiss it would otherwise have to find the pane themselves.
    static func requestAccess() {
        // `kAXTrustedCheckOptionPrompt` is declared without `const`, so Swift
        // imports it as a global var that strict concurrency refuses to read.
        // The literal is the documented key behind that constant.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Places the main window of each app (by bundle id, in order) into the
    /// layout's slots on `screen` (default: the screen with the key window).
    /// Apps that are not running or never show a window are skipped, and the
    /// next app takes the next slot — a playbook whose second app failed to
    /// launch should not leave a hole in the middle of the screen. With more
    /// apps than slots the extras stack on the last slot.
    func arrange(bundleIDs: [String], layout: WindowLayout, on screen: NSScreen? = nil) async {
        let trusted = Self.isTrusted
        log.info("arrange layout=\(layout.rawValue, privacy: .public) apps=\(bundleIDs.count, privacy: .public) trusted=\(trusted, privacy: .public)")
        guard trusted else {
            log.notice("accessibility not granted — skipping layout")
            return
        }
        guard layout != .none, let screen = screen ?? NSScreen.main else { return }
        let frames = Self.slotFrames(for: layout, on: screen)
        guard !frames.isEmpty else { return }

        var slot = 0
        for bundleID in bundleIDs {
            let frame = frames[min(slot, frames.count - 1)]
            if await place(bundleID: bundleID, in: frame) {
                slot += 1
            }
        }
    }

    // MARK: - Geometry

    /// Cocoa measures from the bottom-left of the primary display with y up;
    /// Accessibility measures from the top-left of the same display with y
    /// down. Both share the x axis and the primary display's height, so a
    /// Cocoa rect's top edge lands at `primaryHeight - maxY` in AX space.
    /// Secondary displays fall out of this automatically because their
    /// Cocoa frames are already expressed relative to the primary one.
    private static func slotFrames(for layout: WindowLayout, on screen: NSScreen) -> [CGRect] {
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.maxY
        let axOrigin = CGPoint(x: visible.minX, y: primaryHeight - visible.maxY)
        return layout.slots.map { slot in
            CGRect(
                x: axOrigin.x + slot.minX * visible.width,
                y: axOrigin.y + slot.minY * visible.height,
                width: slot.width * visible.width,
                height: slot.height * visible.height
            ).integral
        }
    }

    // MARK: - Placement

    /// Returns true when a window was moved, false when the app was skipped.
    private func place(bundleID: String, in frame: CGRect) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let app = running.first(where: { !$0.isTerminated }) else {
            log.info("skip \(bundleID, privacy: .public): not running")
            return false
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = await waitForStandardWindow(of: appElement, bundleID: bundleID) else {
            log.info("skip \(bundleID, privacy: .public): no standard window")
            return false
        }

        if Self.bool(window, kAXMinimizedAttribute) == true {
            log.info("\(bundleID, privacy: .public): un-minimizing")
            Self.set(window, kAXMinimizedAttribute, false as CFBoolean)
            try? await Task.sleep(for: .milliseconds(300))
        }
        // No public constant for this one; "AXFullScreen" is what the
        // Accessibility Inspector shows and what every window manager uses.
        if Self.bool(window, "AXFullScreen") == true {
            log.info("\(bundleID, privacy: .public): leaving fullscreen")
            Self.set(window, "AXFullScreen", false as CFBoolean)
            try? await Task.sleep(for: .milliseconds(600))
        }

        Self.setFrame(window, frame)
        let actual = Self.frame(of: window)
        log.info("arranged \(bundleID, privacy: .public) target=\(Self.describe(frame), privacy: .public) actual=\(Self.describe(actual), privacy: .public)")
        return true
    }

    /// Polls for a standard window; apps launched a moment ago need time to
    /// finish restoring state before AX reports anything.
    private func waitForStandardWindow(of app: AXUIElement, bundleID: String) async -> AXUIElement? {
        for attempt in 0..<Self.windowWaitAttempts {
            if let window = Self.standardWindow(of: app) { return window }
            if attempt == 0 {
                log.debug("\(bundleID, privacy: .public): waiting for a window")
            }
            try? await Task.sleep(for: Self.windowWaitInterval)
        }
        return nil
    }

    /// The focused/main window if it is a regular document window, otherwise
    /// the first regular window in the app's list. Panels, sheets and
    /// floating palettes report other subroles and are left alone.
    private static func standardWindow(of app: AXUIElement) -> AXUIElement? {
        var candidates: [AXUIElement] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = copy(app, attribute), CFGetTypeID(window) == AXUIElementGetTypeID() {
                candidates.append(window as! AXUIElement)
            }
        }
        if let windows = copy(app, kAXWindowsAttribute) as? [AXUIElement] {
            candidates.append(contentsOf: windows)
        }
        return candidates.first { window in
            (copy(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole
        }
    }

    /// Position, then size, then position again: some apps clamp the size to
    /// a minimum and shift the window to keep it on screen, which undoes the
    /// first move.
    private static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else { return }
        set(window, kAXPositionAttribute, position)
        set(window, kAXSizeAttribute, dimensions)
        set(window, kAXPositionAttribute, position)
    }

    private static func frame(of window: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let value = copy(window, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgPoint, &origin)
        }
        if let value = copy(window, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - AX plumbing

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copy(element, attribute) as? Bool
    }

    @discardableResult
    private static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    private static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
    }
}
