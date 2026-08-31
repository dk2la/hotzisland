import AppKit
import SwiftUI

/// Icons and display names of the apps a playbook opens — the fastest way
/// to tell rows apart at a glance. Looked up once per bundle id, cached for
/// the app's lifetime (workspace lookups touch the disk).
@MainActor
enum AppVisuals {
    private static var icons: [String: NSImage?] = [:]
    private static var names: [String: String?] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        let image = url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = image
        return image
    }

    static func name(for bundleID: String) -> String? {
        if let cached = names[bundleID] { return cached }
        let name = url(for: bundleID).map {
            FileManager.default.displayName(atPath: $0.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        names[bundleID] = name
        return name
    }

    private static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

/// "Playbooks" module: full-width workspace rows — a stack of the real app
/// icons, the name over the apps it opens, and a Launch button. A quiet
/// register underneath reports the last run.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(store.playbooks) { playbook in
                        row(for: playbook)
                    }
                }
            }
            if let last = runner.lastRun {
                runRegister(last)
            }
        }
    }

    // MARK: - Rows

    /// Same row language as the other lists (clipboard, notes): the whole
    /// row is the button, a small square affordance trails. A text capsule
    /// would wrap at narrow widths — an icon cannot.
    private func row(for playbook: Playbook) -> some View {
        let isLastRun = runner.lastRun?.playbook.id == playbook.id
        return Button {
            runner.run(playbook)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                identity(for: playbook)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playbook.name)
                        .font(Theme.bodyFont)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle(for: playbook))
                        .font(Theme.captionFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textQuaternary)
                }
                Spacer(minLength: 0)
                Image(systemName: isLastRun ? "checkmark" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isLastRun ? Theme.inkOnAccent : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isLastRun ? Theme.accent : Theme.raisedFill)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(runner.isRunning)
        .opacity(runner.isRunning ? 0.5 : 1)
    }

    /// Overlapping icons of the apps the playbook opens; the user-chosen
    /// symbol fills in for shortcut-only playbooks.
    @ViewBuilder
    private func identity(for playbook: Playbook) -> some View {
        let icons = playbook.openBundleIDs.prefix(3).compactMap(AppVisuals.icon(for:))
        if icons.isEmpty {
            Image(systemName: playbook.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.raisedFill)
                )
        } else {
            HStack(spacing: -9) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        // A hairline moat so overlapped icons read as a stack.
                        .background(Circle().fill(Theme.cardFill).padding(-1))
                }
            }
            .frame(minWidth: 30, alignment: .leading)
        }
    }

    /// "Zed · Terminal · Firefox" — the apps themselves, by name; falls back
    /// to the behavioural meta for playbooks that open nothing.
    private func subtitle(for playbook: Playbook) -> String {
        let names = playbook.openBundleIDs.compactMap(AppVisuals.name(for:))
        if !names.isEmpty {
            let shown = names.prefix(3).joined(separator: " · ")
            let more = names.count > 3 ? " +\(names.count - 3)" : ""
            return shown + more
        }
        var parts: [String] = []
        if playbook.closeOthers { parts.append(L10n.t(.playCloseRest)) }
        if playbook.shortcutName != nil { parts.append(L10n.t(.playFocus)) }
        if let minutes = playbook.timerMinutes { parts.append("\(minutes)m") }
        return parts.isEmpty ? L10n.t(.playEmpty) : parts.joined(separator: " · ")
    }

    // MARK: - Run register

    /// "«Работа» — закрыто 6, открыто 4". Quiet by design: it is a receipt,
    /// not an alert — unless something failed.
    private func runRegister(_ last: PlaybookRunner.RunRecord) -> some View {
        let failed = !last.result.failures.isEmpty
        return HStack(spacing: 10) {
            Circle()
                .fill(failed ? Theme.critical : Theme.accent)
                .frame(width: 5, height: 5)
            Text(summary(last))
                .font(Theme.subFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func summary(_ last: PlaybookRunner.RunRecord) -> String {
        var parts: [String] = []
        if last.result.closed > 0 { parts.append(L10n.f(.playClosed, last.result.closed)) }
        if last.result.opened > 0 { parts.append(L10n.f(.playOpened, last.result.opened)) }
        if !last.result.failures.isEmpty { parts.append(L10n.f(.playErrors, last.result.failures.count)) }
        let detail = parts.isEmpty ? L10n.t(.playDone) : parts.joined(separator: ", ")
        return "«\(last.playbook.name)» — \(detail)"
    }
}

extension Notification.Name {
    /// Posted by island UI that wants the settings window opened.
    static let hotzOpenSettings = Notification.Name("hotzOpenSettings")
}
