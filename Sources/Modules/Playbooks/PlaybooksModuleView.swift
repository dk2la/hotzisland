import SwiftUI

/// "Play" channel: playbook cards with status dots, a dashed "+ new" card
/// and an amber run-confirmation register.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 8)]

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
                if isLastRun {
                    BlinkingDot(size: 6)
                } else {
                    Circle()
                        .fill(Theme.textPrimary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
                Spacer(minLength: 0)
                Text(playbook.name)
                    .font(Theme.headlineFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                InstrumentLabel(subtitle(for: playbook))
                    .padding(.top, 3)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 84)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(isLastRun ? Theme.amberBorder : Theme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(runner.isRunning)
        .opacity(runner.isRunning ? 0.5 : 1)
    }

    private var newCard: some View {
        Button {
            NotificationCenter.default.post(name: .hotzOpenSettings, object: nil)
        } label: {
            DashedZone(label: "+ new")
                .frame(height: 84)
                .contentShape(Rectangle())
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
        return parts.isEmpty ? "empty" : parts.joined(separator: " · ")
    }

    /// "run · «Работа» — закрыто 6, открыто 4"
    private func runRegister(_ last: PlaybookRunner.RunRecord) -> some View {
        HStack(spacing: 10) {
            BlinkingDot(size: 6)
            InstrumentLabel("run", color: Theme.amber)
            Text(summary(last))
                .font(Theme.subFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.amberWash, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.amberBorder, lineWidth: 1)
        )
    }

    private func summary(_ last: PlaybookRunner.RunRecord) -> String {
        var parts: [String] = []
        if last.result.closed > 0 { parts.append("закрыто \(last.result.closed)") }
        if last.result.opened > 0 { parts.append("открыто \(last.result.opened)") }
        if !last.result.failures.isEmpty { parts.append("ошибок \(last.result.failures.count)") }
        let detail = parts.isEmpty ? "выполнен" : parts.joined(separator: ", ")
        return "«\(last.playbook.name)» — \(detail)"
    }
}

extension Notification.Name {
    /// Posted by island UI that wants the settings window opened.
    static let hotzOpenSettings = Notification.Name("hotzOpenSettings")
}
