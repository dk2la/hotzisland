import SwiftUI

/// Surface palette of the capsule's settings and tour. They sit on the same
/// dark glass as the widget, so every surface here is a translucent white
/// layer over that glass — never an opaque fill that would hide it.
enum Palette {
    /// Inset wells (editor step lists).
    static let desk = Theme.textPrimary.opacity(0.05)
    /// Page background — the glass itself.
    static let panel = Color.clear
    /// Raised controls and input boxes.
    static let raised = Theme.textPrimary.opacity(0.08)
    /// The settings sidebar: a shade lighter than the page.
    static let sidebar = Theme.textPrimary.opacity(0.04)
    /// Grouped-row cards.
    static let card = Theme.textPrimary.opacity(0.05)
    static let cardStroke = Theme.textPrimary.opacity(0.08)
    static let ink = Theme.textPrimary
    static let ink60 = Theme.textPrimary.opacity(0.6)
    static let ink40 = Theme.textPrimary.opacity(0.4)
    static let hairline = Theme.textPrimary.opacity(0.08)
    static let border = Theme.textPrimary.opacity(0.14)
    static let accent = Theme.accent
    static let accentWash = Theme.accent.opacity(0.10)
}

/// Settings text button. Plain it is a coloured link; `filled` makes it a
/// small secondary pill.
struct PaletteButton: View {
    let title: String
    var color = Palette.accent
    var filled = false
    var vPad: CGFloat = 0
    let action: () -> Void

    init(_ title: String, color: Color = Palette.accent, filled: Bool = false, vPad: CGFloat = 0, action: @escaping () -> Void) {
        (self.title, self.color, self.filled, self.vPad, self.action) = (title, color, filled, vPad, action)
    }

    var body: some View {
        if filled {
            PillButton(title, style: .secondary, size: .small, action: action)
        } else {
            Button(action: action) {
                Text(title)
                    .font(Theme.subFont)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                    .padding(.vertical, vPad)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }
}

/// The pill button of the glass surfaces. Primary is the bright, glossy
/// white key — one per view, for the thing to do next; secondary is
/// raised glass.
struct PillButton: View {
    enum Style {
        case primary
        case secondary
    }

    enum Size {
        case regular
        case small
    }

    let title: String
    var systemName: String?
    var style: Style = .secondary
    var size: Size = .regular
    let action: () -> Void

    init(
        _ title: String,
        systemName: String? = nil,
        style: Style = .secondary,
        size: Size = .regular,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = systemName
        self.style = style
        self.size = size
        self.action = action
    }

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: size == .small ? 10 : 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: size == .small ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(style == .primary ? Theme.inkOnAccent : Theme.textPrimary)
            .padding(.horizontal, size == .small ? 12 : 16)
            .frame(height: size == .small ? 26 : 32)
            .background(fill)
            .overlay(stroke)
            .shadow(color: .black.opacity(style == .primary ? 0.3 : 0), radius: 4, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    @ViewBuilder
    private var fill: some View {
        switch style {
        case .primary:
            // Glossy key: a light top fading to a cooler bottom.
            Capsule().fill(
                LinearGradient(
                    colors: [Color.white, Color(white: hovered ? 0.90 : 0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .secondary:
            Capsule().fill(Theme.textPrimary.opacity(hovered ? 0.14 : 0.10))
        }
    }

    @ViewBuilder
    private var stroke: some View {
        switch style {
        case .primary:
            Capsule().strokeBorder(
                LinearGradient(colors: [.white, .white.opacity(0.4)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        case .secondary:
            Capsule().strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1)
        }
    }
}

/// Round ✕ on glass — the close key of the capsule's panels.
struct GlassCloseButton: View {
    var size: CGFloat = 28
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(hovered ? 1 : 0.8))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.25)))
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// Switch: a capsule track that fills with the accent, a white knob.
struct InstrumentToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Palette.accent : Theme.textPrimary.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(isOn ? 0 : 0.08), lineWidth: 1))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
    }
}

/// Segmented selector: a glass capsule whose selected segment is a raised
/// pill that slides between options.
struct WindowSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    @Namespace private var segment

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isActive = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(Theme.subFont)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(isActive ? Palette.ink : Palette.ink60)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background {
                            if isActive {
                                Capsule()
                                    .fill(Theme.textPrimary.opacity(0.16))
                                    .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 1))
                                    .matchedGeometryEffect(id: "selection", in: segment)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.textPrimary.opacity(0.06)))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
    }
}

extension View {
    /// Selectable chip chrome: raised glass, an accent ring when active.
    func paletteTile(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return background(isActive ? Palette.accentWash : Palette.raised, in: shape)
            .overlay(shape.strokeBorder(isActive ? Palette.accent.opacity(0.5) : Palette.cardStroke, lineWidth: 1))
            .contentShape(shape)
    }
}

/// Settings row: title + explanation on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.subFont)
                        .foregroundStyle(Palette.ink40)
                }
            }
            Spacer(minLength: 0)
            control()
        }
        .padding(.vertical, 12)
    }
}

/// Grouped rows on a glass card — the settings' unit of layout. Rows keep
/// their own hairlines; the card insets them from its edge.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Palette.card))
        .overlay(shape.strokeBorder(Palette.cardStroke, lineWidth: 1))
    }
}

/// Section caption above a card: small, tracked capitals.
struct SettingsSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(Palette.ink40)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }
}

/// Key cap for hotkey display (⌘ ,): a small raised glass tile.
struct KeyCap: View {
    let symbol: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(symbol)
            .font(Theme.mono(11, .medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(shape.fill(Palette.raised))
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
    }
}
