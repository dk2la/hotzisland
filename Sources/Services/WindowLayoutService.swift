import AppKit
import ApplicationServices
import OSLog

/// Where a playbook puts its apps' windows once they are running. Only the
/// arrangements macOS itself offers under Window ▸ Move & Resize, so the
/// result matches the green button: the system owns the geometry, the
/// tile margins and the menu bar/Dock insets, and tiles never overlap.
enum WindowLayout: String, CaseIterable, Identifiable, Sendable {
    case none, leftRight, topBottom, leftAndQuarters, grid2x2, fullscreen

    var id: String { rawValue }

    private var spec: (icon: String, title: L10nKey) {
        switch self {
        case .none: ("rectangle", .playLayoutNone)
        case .leftRight: ("rectangle.split.2x1", .playLayoutLeftRight)
        case .topBottom: ("rectangle.split.1x2", .playLayoutTopBottom)
        case .leftAndQuarters: ("rectangle.lefthalf.inset.filled", .playLayoutLeftQuarters)
        case .grid2x2: ("rectangle.split.2x2", .playLayoutGrid2x2)
        case .fullscreen: ("rectangle.inset.filled", .playLayoutFullscreen)
        }
    }

    var icon: String { spec.icon }
    @MainActor var title: String { L10n.t(spec.title) }

    /// One system tile per window, in app order — the same split as the
    /// matching Window ▸ Move & Resize ▸ Arrange command.
    fileprivate var tiles: [WindowTile] {
        switch self {
        case .none: []
        case .leftRight: [.left, .right]
        case .topBottom: [.top, .bottom]
        case .leftAndQuarters: [.left, .topRight, .bottomRight]
        case .grid2x2: [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .fullscreen: [.fill]
        }
    }
}

extension WindowLayout: Codable {
    /// Earlier builds offered layouts macOS has no command for; they map to
    /// the closest system arrangement instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "thirds": self = .leftAndQuarters
        case "mainAndSide": self = .leftRight
        default: self = WindowLayout(rawValue: raw) ?? .none
        }
    }
}

/// A tiling command macOS adds to every AppKit app's Window menu. The raw
/// value is the menu item's identifier — AppKit sets it to the action's
/// selector, so it is the same in every interface language.
private enum WindowTile: String {
    case left = "_zoomLeft:"
    case right = "_zoomRight:"
    case top = "_zoomTop:"
    case bottom = "_zoomBottom:"
    case topLeft = "_zoomTopLeft:"
    case topRight = "_zoomTopRight:"
    case bottomLeft = "_zoomBottomLeft:"
    case bottomRight = "_zoomBottomRight:"
    case fill = "_zoomFill:"

    /// Fallback for apps without the system menu (non-AppKit toolkits): the
    /// tile as a fraction of the visible frame, in the unit square with a
    /// top-left origin and y growing downwards — the orientation
    /// Accessibility uses, so the flip from Cocoa happens once per screen.
    var unitRect: CGRect {
        switch self {
        case .left: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .top: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottom: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .fill: CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }
}

extension NSWorkspace {
    /// System Settings ▸ Privacy & Security ▸ `pane` ("Calendars", "Automation"…).
    func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") else { return }
        open(url)
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
    private let log = Logger(subsystem: "com.dk2la.pocket", category: "playbooks")

    /// How long to wait for a freshly launched app to show a window.
    private static let windowWaitAttempts = 12
    private static let windowWaitInterval: Duration = .milliseconds(250)
    /// How long to wait for an app to come forward before tiling its window.
    private static let activationAttempts = 10
    private static let activationInterval: Duration = .milliseconds(50)
    /// macOS animates a tile into place; the next app waits for it.
    private static let tileSettle: Duration = .milliseconds(350)

    /// Whether the user granted Accessibility to this process.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Jumps to the Accessibility pane with the drag-Pocket-into-the-list
    /// hint docked to it. No system dialog on top: it only offers "Open
    /// System Settings", which the hint already did.
    static func requestAccess(onGranted: (() -> Void)? = nil) {
        PermissionGuide.shared.show(.accessibility, onGranted: onGranted)
    }

    /// Tiles the main window of each app (by bundle id, in order) with the
    /// layout's system commands. macOS tiles a window on the display it is
    /// on; `screen` (default: the screen with the key window) only matters
    /// for the fallback frames of apps without the tiling menu.
    /// Apps that are not running or never show a window are skipped, and the
    /// next app takes the next tile — a playbook whose second app failed to
    /// launch should not leave a hole in the middle of the screen. With more
    /// apps than tiles the extras stack on the last tile.
    func arrange(bundleIDs: [String], layout: WindowLayout, on screen: NSScreen? = nil) async {
        let trusted = Self.isTrusted
        log.info("arrange layout=\(layout.rawValue, privacy: .public) apps=\(bundleIDs.count, privacy: .public) trusted=\(trusted, privacy: .public)")
        guard trusted else {
            log.notice("accessibility not granted — skipping layout")
            return
        }
        guard layout != .none, let screen = screen ?? NSScreen.main else { return }
        let tiles = layout.tiles
        guard !tiles.isEmpty else { return }

        var slot = 0
        for bundleID in bundleIDs {
            let tile = tiles[min(slot, tiles.count - 1)]
            if await place(bundleID: bundleID, in: tile, on: screen) {
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
    private static func fallbackFrame(for tile: WindowTile, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.maxY
        let axOrigin = CGPoint(x: visible.minX, y: primaryHeight - visible.maxY)
        let unit = tile.unitRect
        return CGRect(
            x: axOrigin.x + unit.minX * visible.width,
            y: axOrigin.y + unit.minY * visible.height,
            width: unit.width * visible.width,
            height: unit.height * visible.height
        ).integral
    }

    // MARK: - Placement

    /// Returns true when a window was moved, false when the app was skipped.
    private func place(bundleID: String, in tile: WindowTile, on screen: NSScreen) async -> Bool {
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

        if await applySystemTile(tile, to: window, of: app, element: appElement) {
            let actual = Self.frame(of: window)
            log.info("tiled \(bundleID, privacy: .public) via \(tile.rawValue, privacy: .public) actual=\(Self.describe(actual), privacy: .public)")
            return true
        }

        let frame = Self.fallbackFrame(for: tile, on: screen)
        Self.setFrame(window, frame)
        let actual = Self.frame(of: window)
        log.info("no system tile for \(bundleID, privacy: .public) — placed target=\(Self.describe(frame), privacy: .public) actual=\(Self.describe(actual), privacy: .public)")
        return true
    }

    /// Presses the tile's command in the app's own Window menu — exactly
    /// what the user would pick by hand. The command acts on the app's key
    /// window, so the app comes forward and the window is raised first.
    /// False when the app has no such item (non-AppKit toolkits) or it is
    /// disabled (a window macOS refuses to tile).
    private func applySystemTile(
        _ tile: WindowTile, to window: AXUIElement, of app: NSRunningApplication, element appElement: AXUIElement
    ) async -> Bool {
        app.activate()
        for _ in 0..<Self.activationAttempts where !app.isActive {
            try? await Task.sleep(for: Self.activationInterval)
        }
        Self.set(window, kAXMainAttribute, true as CFBoolean)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        guard let item = Self.menuItem(tile.rawValue, in: appElement),
              Self.bool(item, kAXEnabledAttribute) != false,
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        else { return false }
        // Let the tiling animation land before the next app takes focus.
        try? await Task.sleep(for: Self.tileSettle)
        return true
    }

    /// The menu item with `identifier`, looked up only in the menu that
    /// holds the system window commands — the Window menu, whatever its
    /// localized title. Walking every menu of a large app costs hundreds of
    /// IPC round trips.
    private static func menuItem(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        guard let bar = copy(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        // The Window menu sits next to Help, so search from the right.
        for barItem in children(of: bar as! AXUIElement).reversed() {
            for menu in children(of: barItem) where isWindowMenu(menu) {
                return find(identifier, in: menu, depth: 1)
            }
        }
        return nil
    }

    /// Fill and Minimize sit at the top level of the Window menu.
    private static func isWindowMenu(_ menu: AXUIElement) -> Bool {
        children(of: menu).contains { item in
            guard let identifier = copy(item, kAXIdentifierAttribute) as? String else { return false }
            return identifier == WindowTile.fill.rawValue || identifier == "performMiniaturize:"
        }
    }

    /// Depth-first through `depth` levels of submenus (Move & Resize).
    private static func find(_ identifier: String, in menu: AXUIElement, depth: Int) -> AXUIElement? {
        for item in children(of: menu) {
            if copy(item, kAXIdentifierAttribute) as? String == identifier { return item }
            guard depth > 0 else { continue }
            for submenu in children(of: item) {
                if let found = find(identifier, in: submenu, depth: depth - 1) { return found }
            }
        }
        return nil
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

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        copy(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
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
