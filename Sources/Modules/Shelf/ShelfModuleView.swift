import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Shelf" module, V3: a dashed drop tile on top, then file rows — icon
/// tile, name over meta, remove circle. Items drag out; click opens.
struct ShelfModuleView: View {
    var shelf: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            dropTile
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(shelf.items) { item in
                        itemRow(item)
                    }
                }
            }
            HStack {
                Text(L10n.t(.shelfLinksNote))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 0)
                if !shelf.items.isEmpty {
                    GlassCapsuleButton(label: L10n.t(.clipClear)) {
                        shelf.clear()
                    }
                }
            }
        }
    }

    private var dropTile: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(L10n.t(.shelfDrop))
                .font(Theme.subFont)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: shelf.items.isEmpty ? 84 : 52)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
        )
    }

    private func itemRow(_ item: ShelfStore.Item) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 26, height: 26)
                .padding(5)
                .background(Theme.raisedFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.sizeLabel(for: item.url))
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textQuaternary)
            }
            Spacer(minLength: 0)
            Button {
                shelf.remove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raisedFill))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onTapGesture {
            NSWorkspace.shared.open(item.url)
        }
    }

    private static func sizeLabel(for url: URL) -> String {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
        else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
