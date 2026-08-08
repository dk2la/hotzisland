import SwiftUI

/// "Playbooks" tab: one button per scenario. Editing happens in Settings.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        if store.playbooks.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(Theme.iconLargeFont)
                    .foregroundStyle(Theme.textQuaternary)
                Text("Create playbooks in Settings")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.playbooks) { playbook in
                        button(for: playbook)
                    }
                }
            }
        }
    }

    private func button(for playbook: Playbook) -> some View {
        Button {
            runner.run(playbook)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: playbook.icon)
                    .font(Theme.iconFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(playbook.name)
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.surfaceRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
        .opacity(runner.isRunning ? 0.5 : 1)
    }
}
