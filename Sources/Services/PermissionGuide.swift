import AppKit
import EventKit
import SwiftUI

/// Opens System Settings ▸ Privacy & Security on a pane and docks a hint to
/// the bottom of its window: what to do there and, where the list takes
/// drops (Accessibility), Pocket itself as a row to drag into it. The hint
/// follows the window, hides while System Settings is in the background,
/// and goes away once access is granted or the window closes.
@MainActor
final class PermissionGuide {
    enum Permission {
        case accessibility
        case calendars

        fileprivate var pane: String {
            switch self {
            case .accessibility: "Accessibility"
            case .calendars: "Calendars"
            }
        }

        @MainActor fileprivate var title: String {
            switch self {
            case .accessibility: L10n.t(.permAccessibility)
            case .calendars: L10n.t(.permCalendars)
            }
        }

        /// The Accessibility list adds a dropped app; the Calendars one
        /// only lists apps that asked, to be switched on.
        fileprivate var acceptsDrop: Bool { self == .accessibility }

        fileprivate var isGranted: Bool {
            switch self {
            case .accessibility: AXIsProcessTrusted()
            case .calendars: EKEventStore.authorizationStatus(for: .event) == .fullAccess
            }
        }
    }

    static let shared = PermissionGuide()

    private var panel: CapsulePanel?
    private var followTask: Task<Void, Never>?

    private static let settingsBundleID = "com.apple.systempreferences"
    private static let followInterval: Duration = .milliseconds(200)
    /// System Settings may take a while to come up cold.
    private static let launchTimeout: Duration = .seconds(10)
    private static let lifetime: Duration = .seconds(600)
    private static let size = CGSize(width: 460, height: 124)
    private static let inset: CGFloat = 14

    private init() {}

    var isShowing: Bool { panel != nil }

    /// `onGranted` runs once, when the guide sees access come through.
    func show(_ permission: Permission, onGranted: (() -> Void)? = nil) {
        dismiss()
        NSWorkspace.shared.openPrivacyPane(permission.pane)

        let panel = CapsulePanel()
        // Above System Settings, below menus and the capsule.
        panel.level = .floating
        panel.hasShadow = true
        let view = PermissionGuideView(permission: permission) { [weak self] in
            self?.dismiss()
        }
        let hostingView = CapsuleHostingView(rootView: view)
        panel.contentView = hostingView.makeWindowContentView()
        self.panel = panel

        followTask = Task { [weak self] in
            let started = ContinuousClock.now
            var sawWindow = false
            while !Task.isCancelled {
                guard let self else { return }
                if permission.isGranted {
                    self.dismiss()
                    onGranted?()
                    return
                }
                let elapsed = ContinuousClock.now - started
                if let frame = Self.settingsWindowFrame() {
                    sawWindow = true
                    self.place(panel, over: frame)
                } else if sawWindow || elapsed > Self.launchTimeout {
                    // Closed, or never showed up.
                    self.dismiss()
                    return
                } else {
                    panel.orderOut(nil)
                }
                if elapsed > Self.lifetime {
                    self.dismiss()
                    return
                }
                try? await Task.sleep(for: Self.followInterval)
            }
        }
    }

    func dismiss() {
        followTask?.cancel()
        followTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Over the bottom of the window, centered. Shown only while System
    /// Settings is frontmost — a floating hint over other apps would be
    /// litter.
    private func place(_ panel: NSPanel, over window: CGRect) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.settingsBundleID else {
            panel.orderOut(nil)
            return
        }
        let width = min(Self.size.width, window.width - 2 * Self.inset)
        let frame = NSRect(
            x: window.midX - width / 2,
            y: window.minY + Self.inset,
            width: width,
            height: Self.size.height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// System Settings' main window in AppKit screen coordinates. Window
    /// bounds and owners are readable without Screen Recording access —
    /// only titles are not.
    private static func settingsWindowFrame() -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).first,
              let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let pid = app.processIdentifier
        let frames = list.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 200, rect.height > 200
            else { return nil }
            return rect
        }
        guard let rect = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
        // Core Graphics counts from the top of the primary screen.
        return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// The hint itself: an arrow up at the list, the instruction, and Pocket
/// as a row — draggable where the pane takes it.
private struct PermissionGuideView: View {
    let permission: PermissionGuide.Permission
    let onClose: () -> Void

    @State private var rowHovered = false

    private static let appName = "Pocket"

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrowshape.up.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.55, blue: 1))
                    .shadow(color: Color.blue.opacity(0.5), radius: 6)
                    .frame(width: 36)
                Text(hint)
                    .font(.system(size: 14))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                GlassCloseButton(size: 36, action: onClose)
                appRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(shape.fill(Color(white: 0.13).opacity(0.97)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }

    /// The instruction, with the app and the permission picked out.
    private var hint: AttributedString {
        let template = L10n.t(permission.acceptsDrop ? .permDragHint : .permToggleHint)
        var text = AttributedString(
            template
                .replacingOccurrences(of: "{app}", with: Self.appName)
                .replacingOccurrences(of: "{perm}", with: permission.title)
        )
        text.foregroundColor = Color.white.opacity(0.55)
        for word in [Self.appName, permission.title] {
            if let range = text.range(of: word) {
                text[range].foregroundColor = .white
            }
        }
        return text
    }

    @ViewBuilder
    private var appRow: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let row = HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            Text(Self.appName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(shape.fill(Color.white.opacity(rowHovered && permission.acceptsDrop ? 0.1 : 0.06)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .contentShape(shape)
        .onHover { rowHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: rowHovered)

        if permission.acceptsDrop {
            row.onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        } else {
            row
        }
    }
}
