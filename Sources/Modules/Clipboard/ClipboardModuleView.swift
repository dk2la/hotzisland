import SwiftUI

/// "Clipboard" tab: recent text snippets; click puts one back on the
/// pasteboard.
struct ClipboardModuleView: View {
    var clipboard: ClipboardStore
    @State private var copiedID: UUID?

    var body: some View {
        if clipboard.entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(Theme.iconLargeFont)
                    .foregroundStyle(Theme.textQuaternary)
                Text("Copied text will appear here")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(clipboard.entries) { entry in
                            row(entry)
                        }
                    }
                }
                Button {
                    clipboard.clear()
                } label: {
                    Text("Clear")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ entry: ClipboardStore.Entry) -> some View {
        Button {
            clipboard.copy(entry)
            copiedID = entry.id
            Task {
                try? await Task.sleep(for: .seconds(1))
                if copiedID == entry.id { copiedID = nil }
            }
        } label: {
            HStack(spacing: 8) {
                Text(entry.text)
                    .font(Theme.captionFont)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                    .font(Theme.captionFont)
                    .foregroundStyle(copiedID == entry.id ? Theme.accentPositive : Theme.textQuaternary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
