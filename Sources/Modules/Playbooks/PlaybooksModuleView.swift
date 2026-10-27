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

/// "Playbooks" module: the last-run playbook as a hero card with Run, the
/// rest as one grouped list — symbol, name over a one-line recipe of its
/// steps, a run button — ending in "Add playbook…", which opens the editor
/// in Settings. A quiet register underneath reports failures of the last
/// run.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    /// Playbook that just finished — it shows a checkmark for 3 s.
    @State private var justRanID: UUID?

    /// The hero: the last playbook run, else the first one.
    private var featured: Playbook? {
        if let last = runner.lastRun,
           let current = store.playbooks.first(where: { $0.id == last.playbook.id }) {
            return current
        }
        return store.playbooks.first
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if let featured {
                        hero(featured)
                    }
                    list(store.playbooks.filter { $0.id != featured?.id })
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

    // MARK: - Hero

    private func hero(_ playbook: Playbook) -> some View {
        let isRunningThis = runner.runningPlaybookID == playbook.id
        return HeroCard {
            if let last = runner.lastRun, last.playbook.id == playbook.id {
                HStack(spacing: 7) {
                    StatusDot()
                    Text(L10n.f(.playLastRun, Self.timeFormatter.string(from: last.finishedAt)))
                        .heroCaption()
                        .monospacedDigit()
                }
            }
            HStack(spacing: 12) {
                IconTile(systemName: playbook.icon, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playbook.name)
                        .font(Theme.heroFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary(for: playbook))
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(appIDs(of: playbook).prefix(6), id: \.self) { bundleID in
                    if let icon = AppVisuals.icon(for: bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .help(AppVisuals.name(for: bundleID) ?? bundleID)
                    }
                }
                Spacer(minLength: 0)
                ModuleButton(
                    label: L10n.t(.asstPlaybookRun),
                    systemName: justRanID == playbook.id ? "checkmark" : "play.fill",
                    kind: .accent,
                    height: 34,
                    enabled: !runner.isRunning || isRunningThis
                ) {
                    runner.run(playbook)
                }
            }
        }
    }

    /// Apps the playbook opens, in step order.
    private func appIDs(of playbook: Playbook) -> [String] {
        playbook.steps.flatMap { step -> [String] in
            if case .openApps(_, let bundleIDs, _) = step { return bundleIDs }
            return []
        }
    }

    private static let timeFormatter = DateFormatter(format: "HH:mm")

    // MARK: - List

    private func list(_ playbooks: [Playbook]) -> some View {
        GroupedCard {
            ForEach(playbooks) { playbook in
                row(for: playbook)
            }
            newRow
        }
    }

    private func row(for playbook: Playbook) -> some View {
        let isRunningThis = runner.runningPlaybookID == playbook.id
        let justRan = justRanID == playbook.id
        return HStack(alignment: .center, spacing: 12) {
            IconTile(systemName: playbook.icon)
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
            CircleGlassButton(systemName: "play.fill", size: 30, solid: isRunningThis) {
                runner.run(playbook)
            }
            .disabled(runner.isRunning)
            .opacity(runner.isRunning && !isRunningThis ? 0.5 : 1)
        }
        .groupedRow(isLast: false)
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
                parts.append(L10n.f(.ageMin, minutes))
            case .openURLs(_, let urls):
                parts.append(L10n.f(.playLinks, urls.count))
            }
        }
        return parts.isEmpty ? L10n.t(.playEmpty) : parts.joined(separator: " · ")
    }

    /// The last row: the only way to create a playbook from the widget —
    /// deep-links to Settings → Playbooks.
    private var newRow: some View {
        Button {
            requestSettings(page: .playbooks)
        } label: {
            HStack(spacing: 12) {
                IconTile(systemName: "plus", dashed: true)
                Text(L10n.t(.playAdd))
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .groupedRow(isLast: true)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
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
