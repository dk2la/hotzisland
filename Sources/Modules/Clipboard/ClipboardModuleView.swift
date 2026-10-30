import SwiftUI

/// "Clipboard" module: the latest copy as a hero card with its first lines
/// and a Copy button, older entries as one grouped list. Clicking anything
/// puts that entry back on the pasteboard; the button flips to an accent
/// "Copied" for a second.
struct ClipboardModuleView: View {
    var clipboard: ClipboardStore

    @State private var copiedID: UUID?

    var body: some View {
        if let latest = clipboard.entries.first {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        hero(latest)
                        let earlier = Array(clipboard.entries.dropFirst())
                        if !earlier.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: L10n.t(.mailSectionEarlier))
                                GroupedCard {
                                    ForEach(Array(earlier.enumerated()), id: \.element.id) { index, entry in
                                        row(entry, isLast: index == earlier.count - 1)
                                    }
                                }
                            }
                        }
                    }
                }
                // Clearing lives in the panel header; the footer is a quiet
                // disclosure line, same register as the mail status row.
                HStack(spacing: 7) {
                    Image(systemName: "lock")
                        .font(.system(size: 10, weight: .medium))
                    Text(L10n.t(.clipMemoryNote))
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
            }
        } else {
            EmptyStateZone(label: L10n.t(.clipEmptyTitle), sublabel: L10n.t(.clipEmptySub))
                .frame(maxHeight: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hero(_ entry: ClipboardStore.Entry) -> some View {
        let isCopied = copiedID == entry.id
        return Button {
            copy(entry)
        } label: {
            HeroCard {
                HStack(spacing: 0) {
                    Text(L10n.t(.clipLatest))
                        .heroCaption()
                    Text(" · \(Self.age(of: entry)) · \(Self.kind(of: entry))")
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(Theme.bodyFont)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer(minLength: 0)
                    // The whole card copies; this is the visible affordance.
                    Label(
                        L10n.t(isCopied ? .clipCopied : .clipCopy),
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(Theme.subFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.inkOnAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        isCopied ? Theme.accent : Theme.lightFill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
            }
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.15), value: isCopied)
    }

    private func row(_ entry: ClipboardStore.Entry, isLast: Bool) -> some View {
        let isCopied = copiedID == entry.id
        return Button {
            copy(entry)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                IconTile(systemName: Self.isLink(entry) ? "link" : "text.alignleft")
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                        .font(Theme.bodyFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Self.age(of: entry)) · \(Self.kind(of: entry))")
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                if isCopied {
                    Label(L10n.t(.clipCopied), systemImage: "checkmark")
                        .font(Theme.subFont)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.raisedFill))
                }
            }
            .groupedRow(isLast: isLast)
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.15), value: isCopied)
    }

    private func copy(_ entry: ClipboardStore.Entry) {
        clipboard.copy(entry)
        copiedID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1))
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private static func age(of entry: ClipboardStore.Entry) -> String {
        L10n.age(since: entry.copiedAt)
    }

    private static func isLink(_ entry: ClipboardStore.Entry) -> Bool {
        entry.text.hasPrefix("http://") || entry.text.hasPrefix("https://")
    }

    private static func kind(of entry: ClipboardStore.Entry) -> String {
        isLink(entry) ? L10n.t(.kindLink) : L10n.t(.kindText)
    }
}
