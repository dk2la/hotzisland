import SwiftUI

/// "Clipboard" module, V3: entries as raised-glass rows — text over a meta
/// caption, a copy circle on the right that flips to a solid "Готово"
/// capsule after copying. Click puts an entry back on the pasteboard.
struct ClipboardModuleView: View {
    var clipboard: ClipboardStore
    @State private var copiedID: UUID?

    var body: some View {
        if clipboard.entries.isEmpty {
            EmptyStateZone(label: L10n.t(.clipEmptyTitle), sublabel: L10n.t(.clipEmptySub))
                .frame(maxHeight: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(clipboard.entries) { entry in
                            row(entry)
                        }
                    }
                }
                // Clearing moved to the panel header; the footer is a quiet
                // disclosure line, same register as the mail status row.
                Text(L10n.t(.clipMemoryNote))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func row(_ entry: ClipboardStore.Entry) -> some View {
        let isCopied = copiedID == entry.id
        return Button {
            clipboard.copy(entry)
            copiedID = entry.id
            Task {
                try? await Task.sleep(for: .seconds(1))
                if copiedID == entry.id { copiedID = nil }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                        .font(Theme.bodyFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Self.age(of: entry)) · \(Self.kind(of: entry))")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textQuaternary)
                }
                Spacer(minLength: 0)
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text(L10n.t(.clipCopied))
                            .font(Theme.captionFont)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.inkOnAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raisedFill))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private static func age(of entry: ClipboardStore.Entry) -> String {
        let minutes = Int(Date().timeIntervalSince(entry.copiedAt) / 60)
        if minutes < 1 { return L10n.t(.ageNow) }
        if minutes < 60 { return L10n.f(.ageMin, minutes) }
        return L10n.f(.ageHour, minutes / 60)
    }

    private static func kind(of entry: ClipboardStore.Entry) -> String {
        entry.text.hasPrefix("http://") || entry.text.hasPrefix("https://")
            ? L10n.t(.kindLink)
            : L10n.t(.kindText)
    }
}
