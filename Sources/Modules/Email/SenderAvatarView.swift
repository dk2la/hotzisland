import SwiftUI

/// Round sender badge: the Gravatar picture when there is one, otherwise
/// initials on a colour derived from the name — the same person always
/// gets the same colour.
struct SenderAvatarView: View {
    let name: String
    let address: String
    var size: CGFloat = 32
    var store: SenderAvatarStore

    var body: some View {
        Group {
            if let image = store.image(for: address) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(Self.initials(name: name, address: address))
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.color(for: address.isEmpty ? name : address))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// "Frank Greeff" → "FG"; an address-only sender uses the local part.
    static func initials(name: String, address: String) -> String {
        let source = name.isEmpty ? String(address.split(separator: "@").first ?? "") : name
        let words = source
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "@" : letters.joined()
    }

    private static let palette: [Color] = [
        Color(red: 0.898, green: 0.400, blue: 0.251), // #E56640
        Color(red: 0.349, green: 0.451, blue: 0.600), // #597399
        Color(red: 0.502, green: 0.349, blue: 0.600), // #805999
        Color(red: 0.600, green: 0.549, blue: 0.302), // #998C4D
        Color(red: 0.302, green: 0.302, blue: 0.349), // #4D4D59
        Color(red: 0.227, green: 0.525, blue: 0.482), // #3A867B
    ]

    /// Stable hash — `hashValue` is randomised per launch.
    static func color(for key: String) -> Color {
        var hash: UInt32 = 5381
        for byte in key.lowercased().utf8 {
            hash = (hash &* 33) &+ UInt32(byte)
        }
        return palette[Int(hash % UInt32(palette.count))]
    }
}
