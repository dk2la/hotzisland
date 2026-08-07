import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Shelf" tab: files parked on the notch. Items drag out to Finder or any
/// app; click opens the file.
struct ShelfModuleView: View {
    var shelf: ShelfStore

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(Theme.iconLargeFont)
                    .foregroundStyle(Theme.textQuaternary)
                Text("Drag files onto the notch")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            itemView(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    shelf.clear()
                } label: {
                    Text("Clear")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func itemView(_ item: ShelfStore.Item) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(item.name)
                .font(Theme.captionFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 68)
        }
        .padding(6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.surfaceRadius))
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
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }
}
