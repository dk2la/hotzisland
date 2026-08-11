import SwiftUI

/// "Clip" channel: history as data registers — relative age, mono content,
/// type tag. Click puts an entry back on the pasteboard.
struct ClipboardModuleView: View {
    var clipboard: ClipboardStore
    @State private var copiedID: UUID?

    var body: some View {
        if clipboard.entries.isEmpty {
            DashedZone(label: "no signal", sublabel: "Скопированный текст появится здесь")
                .frame(maxHeight: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(clipboard.entries) { entry in
                            row(entry)
                            if entry.id != clipboard.entries.last?.id {
                                Hairline()
                            }
                        }
                    }
                }
                HStack {
                    InstrumentLabel("in-memory only · concealed types skipped", color: Theme.textFaint)
                    Spacer(minLength: 0)
                    Button {
                        clipboard.clear()
                    } label: {
                        InstrumentLabel("clear", color: Theme.textQuaternary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Self.age(of: entry))
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 40, alignment: .leading)
                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(Theme.readoutSFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                Spacer(minLength: 0)
                InstrumentLabel(
                    copiedID == entry.id ? "ok" : Self.kind(of: entry),
                    color: copiedID == entry.id ? Theme.amber : Theme.textFaint
                )
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private static func age(of entry: ClipboardStore.Entry) -> String {
        let minutes = Int(Date().timeIntervalSince(entry.copiedAt) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "−\(minutes)m" }
        return "−\(minutes / 60)h"
    }

    private static func kind(of entry: ClipboardStore.Entry) -> String {
        entry.text.hasPrefix("http://") || entry.text.hasPrefix("https://") ? "url" : "txt"
    }
}
