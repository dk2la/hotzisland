import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Shelf" channel: file cards with mono metadata and a permanent dashed
/// drop zone. Items drag out; click opens the file.
struct ShelfModuleView: View {
    var shelf: ShelfStore

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shelf.items) { item in
                        itemCard(item)
                    }
                    DashedZone(label: "drop zone")
                        .frame(height: 96)
                }
            }
            HStack {
                InstrumentLabel("links only — оригиналы остаются на месте", color: Theme.textFaint)
                Spacer(minLength: 0)
                if !shelf.items.isEmpty {
                    Button {
                        shelf.clear()
                    } label: {
                        InstrumentLabel("clear", color: Theme.textQuaternary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func itemCard(_ item: ShelfStore.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            Spacer(minLength: 0)
            Text(item.name)
                .font(Theme.readoutSFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Theme.textPrimary)
            Text(Self.sizeLabel(for: item.url))
                .font(Theme.labelFont)
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 96)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onTapGesture {
            NSWorkspace.shared.open(item.url)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                shelf.remove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(4)
        }
    }

    private static func sizeLabel(for url: URL) -> String {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
        else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
