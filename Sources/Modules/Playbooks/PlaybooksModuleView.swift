import SwiftUI

/// "Playbooks" module, V3: raised-glass tiles — icon top-left, run circle
/// top-right, name over meta — plus a ghost "new" tile and a run register.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.playbooks) { playbook in
                        card(for: playbook)
                    }
                    newCard
                }
            }
            if let last = runner.lastRun {
                runRegister(last)
            }
        }
    }

    private func card(for playbook: Playbook) -> some View {
        let isLastRun = runner.lastRun?.playbook.id == playbook.id
        return Button {
            runner.run(playbook)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: playbook.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    Spacer(minLength: 0)
                    Image(systemName: isLastRun ? "checkmark" : "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isLastRun ? Theme.inkOnAccent : Theme.textPrimary.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isLastRun ? Theme.accent : Theme.raisedFill))
                }
                Spacer(minLength: 0)
                Text(playbook.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary.opacity(0.95))
                Text(subtitle(for: playbook))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 92)
            .background(
                isLastRun ? Theme.accentWash : Theme.cardFill,
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(isLastRun ? Theme.accentBorder : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(runner.isRunning)
        .opacity(runner.isRunning ? 0.5 : 1)
    }

    private var newCard: some View {
        Button {
            NotificationCenter.default.post(name: .hotzOpenSettings, object: nil)
        } label: {
            VStack(spacing: 6) {
                Text(L10n.t(.playNew))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func subtitle(for playbook: Playbook) -> String {
        var parts: [String] = []
        if !playbook.openBundleIDs.isEmpty {
            parts.append("\(playbook.openBundleIDs.count) apps")
        }
        if playbook.closeOthers {
            parts.append("close rest")
        }
        if playbook.shortcutName != nil {
            parts.append("focus")
        }
        if let minutes = playbook.timerMinutes {
            parts.append("\(minutes)m")
        }
        return parts.isEmpty ? L10n.t(.playEmpty) : parts.joined(separator: " · ")
    }

    /// "«Работа» — закрыто 6, открыто 4"
    private func runRegister(_ last: PlaybookRunner.RunRecord) -> some View {
        HStack(spacing: 10) {
            BlinkingDot(size: 6)
            Text(summary(last))
                .font(Theme.subFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.accentBorder, lineWidth: 1)
        )
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
