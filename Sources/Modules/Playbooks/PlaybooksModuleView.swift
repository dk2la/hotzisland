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

/// "Playbooks" module: one card per playbook in the mail-row language —
/// the user-chosen symbol, the name over a one-line recipe of its steps,
/// and a run button. A "+ new" card at the end opens the editor in
/// Settings. A quiet register underneath reports failures of the last run.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    /// Playbook that just finished — its row shows a checkmark for 3 s.
    @State private var justRanID: UUID?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(store.playbooks) { playbook in
                        row(for: playbook)
                    }
                    newCard
                }
            }
            if let last = runner.lastRun, !last.result.failures.isEmpty {
                runRegister(last)
            }
        }
        .onChange(of: runner.lastRun) { _, record in
            guard let record else { return }
            justRanID = record.playbook.id
            Task {
                try? await Task.sleep(for: .seconds(3))
                if justRanID == record.playbook.id, runner.lastRun == record {
                    justRanID = nil
                }
            }
        }
    }

    // MARK: - Rows

    private static let cardShape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)

    private func row(for playbook: Playbook) -> some View {
        let isRunningThis = runner.runningPlaybookID == playbook.id
        let justRan = justRanID == playbook.id
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: playbook.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.raisedFill)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(playbook.name)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textPrimary)
                Text(summary(for: playbook))
                    .font(Theme.subFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            if justRan {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
            CircleGlassButton(systemName: "play.fill", size: 28, solid: isRunningThis) {
                runner.run(playbook)
            }
            .disabled(runner.isRunning)
            .opacity(runner.isRunning && !isRunningThis ? 0.5 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardFill, in: Self.cardShape)
        .animation(.easeOut(duration: 0.15), value: justRan)
    }

    /// "3 apps · Three columns · focus · 25 min" — one token per step.
    private func summary(for playbook: Playbook) -> String {
        var parts: [String] = []
        for step in playbook.steps {
            switch step {
            case .openApps(_, let bundleIDs, let layout):
                parts.append(L10n.f(.playApps, bundleIDs.count))
                if layout != .none { parts.append(layout.title) }
            case .closeOtherApps:
                parts.append(L10n.t(.playCloseRest))
            case .runShortcut(_, let name):
                parts.append(name.isEmpty ? L10n.t(.playStepShortcut) : name)
            case .setFocus:
                parts.append(L10n.t(.playFocus))
            case .startTimer(_, let minutes):
                parts.append(L10n.f(.playMinutesShort, minutes))
            case .openURLs(_, let urls):
                parts.append(L10n.f(.playLinks, urls.count))
            }
        }
        return parts.isEmpty ? L10n.t(.playEmpty) : parts.joined(separator: " · ")
    }

    /// Dashed placeholder card: the only way to create a playbook from the
    /// widget — deep-links to Settings → Playbooks.
    private var newCard: some View {
        Button {
            NotificationCenter.default.post(
                name: .hotzOpenSettings,
                object: nil,
                userInfo: ["page": SettingsView.Page.playbooks.rawValue]
            )
        } label: {
            Text(L10n.t(.playNew))
                .font(Theme.subFont)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Self.cardShape
                        .stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
                )
                .contentShape(Self.cardShape)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Run register

    /// "«Работа» — закрыто 6, ошибок 1". Shown only when something failed:
    /// success already has its checkmark in the row.
    private func runRegister(_ last: PlaybookRunner.RunRecord) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.critical)
                .frame(width: 5, height: 5)
            Text(registerText(last))
                .font(Theme.subFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func registerText(_ last: PlaybookRunner.RunRecord) -> String {
        var parts: [String] = []
        if last.result.closed > 0 { parts.append(L10n.f(.playClosed, last.result.closed)) }
        if last.result.opened > 0 { parts.append(L10n.f(.playOpened, last.result.opened)) }
        if !last.result.failures.isEmpty { parts.append(L10n.f(.playErrors, last.result.failures.count)) }
        let detail = parts.isEmpty ? L10n.t(.playDone) : parts.joined(separator: ", ")
        return "«\(last.playbook.name)» — \(detail)"
    }
}
