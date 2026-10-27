import SwiftUI

// Building blocks of the tour's stages: a widget panel drawn as a picture,
// and the timing helpers its storyboards run on.

/// A widget panel as a picture: the real header grammar (accent mono title,
/// a few inert header glyphs, ✕) over the module's mock content.
struct StagePanel<Accessories: View, Content: View>: View {
    let title: String
    /// Red unread readout after the title, as the mail panel shows it.
    var badge: String?
    /// One level deep — the header starts with a chevron.
    var showsBack = false
    @ViewBuilder var accessories: Accessories
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if showsBack {
                    StageGlyph("chevron.left")
                }
                Text(title.uppercased())
                    .font(Theme.labelFont)
                    .kerning(1.2)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(Theme.readoutSFont)
                        .foregroundStyle(Theme.critical)
                        .padding(.leading, 2)
                }
                Spacer(minLength: 0)
                accessories
                StageGlyph("xmark")
            }
            .padding(.horizontal, Theme.panelInset)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Hairline(color: Theme.hairline)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, Theme.panelInset)
                .padding(.top, Theme.panelInset)
                .padding(.bottom, 12)
        }
    }
}

extension StagePanel where Accessories == EmptyView {
    init(title: String, badge: String? = nil, showsBack: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title: title, badge: badge, showsBack: showsBack, accessories: { EmptyView() }, content: content)
    }
}

/// A header icon as HeaderIconButton draws it — inert; `active` is the
/// accent state a storyboard flips to show the button "pressed".
struct StageGlyph: View {
    let name: String
    var active = false

    init(_ name: String, active: Bool = false) {
        self.name = name
        self.active = active
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(active ? Theme.accent : Theme.textTertiary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Theme.raisedFill : .clear)
            )
            .animation(.easeOut(duration: 0.15), value: active)
    }
}

/// The square accent/ghost button of the modules (play, send), inert.
struct StageButton: View {
    let systemName: String
    var size: CGFloat = 28
    var solid = false
    var pressed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(solid ? Theme.inkOnAccent : Theme.textPrimary)
            .frame(width: size, height: size)
            .background(shape.fill(solid ? Theme.accent : Theme.raisedFill))
            .scaleEffect(pressed ? 0.88 : 1)
            .animation(.easeOut(duration: pressed ? 0.06 : 0.18), value: pressed)
            .animation(.easeOut(duration: 0.15), value: solid)
    }
}

/// Sender badge with initials, coloured the way SenderAvatarView colours
/// a real sender.
struct StageAvatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Text(SenderAvatarView.initials(name: name, address: ""))
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(SenderAvatarView.color(for: name))
            .clipShape(Circle())
    }
}

/// The editor caret: a thin accent bar on the 1 s hardware blink.
struct StageCaret: View {
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: 2, height: height)
                .opacity(on ? 1 : 0)
        }
    }
}

// MARK: - Storyboard timing

/// One beat of a stage storyboard. False once the stage has gone away
/// (page turned, island closed) — the script stops right there.
@MainActor
func beat(_ seconds: Double) async -> Bool {
    try? await Task.sleep(for: .seconds(seconds))
    return !Task.isCancelled
}

/// Runs a looping storyboard for as long as the stage is on screen. With
/// Reduce Motion the stage shows its finished frame instead — the story
/// still reads, nothing moves.
extension View {
    func storyboard(
        finalFrame: @escaping @MainActor () -> Void,
        loop: @escaping @MainActor () async -> Bool
    ) -> some View {
        task {
            if Theme.reduceMotion {
                finalFrame()
                return
            }
            while !Task.isCancelled {
                guard await loop() else { return }
            }
        }
    }
}

/// Typing in units a reader perceives: words where the language spaces
/// them, characters where it does not (Chinese, Japanese).
struct TypedText {
    let full: String
    let units: [String]

    init(_ full: String, byWord: Bool = true) {
        self.full = full
        let spaced = full.filter { $0 == " " }.count >= 3
        if byWord, spaced {
            // Keep the separators attached so prefixes rebuild exactly.
            var parts: [String] = []
            var current = ""
            for character in full {
                current.append(character)
                if character == " " || character == "\n" {
                    parts.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { parts.append(current) }
            units = parts
        } else {
            units = full.map(String.init)
        }
    }

    var count: Int { units.count }

    func prefix(_ n: Int) -> String {
        units.prefix(max(0, n)).joined()
    }
}

/// Sample module colours — the avatar palette, so mock windows and
/// calendars feel like the rest of the app.
enum StagePalette {
    static let blue = Color(red: 0.349, green: 0.451, blue: 0.600)
    static let orange = Color(red: 0.898, green: 0.400, blue: 0.251)
    static let purple = Color(red: 0.502, green: 0.349, blue: 0.600)
    static let teal = Color(red: 0.227, green: 0.525, blue: 0.482)
    static let sand = Color(red: 0.600, green: 0.549, blue: 0.302)
}
