import SwiftUI

/// Window-surface palette (settings, onboarding). V3: windows match the
/// widget and the notch — always the dark rack graphite.
enum Palette {
    static let desk = Color(red: 0.043, green: 0.043, blue: 0.039)   // #0B0B0A
    static let panel = Color(red: 0.071, green: 0.071, blue: 0.067)  // #121211
    static let raised = Color(red: 0.110, green: 0.110, blue: 0.102) // #1C1C1A
    static let ink = Theme.textPrimary
    static let ink60 = Theme.textPrimary.opacity(0.6)
    static let ink40 = Theme.textPrimary.opacity(0.4)
    static let hairline = Theme.textPrimary.opacity(0.09)
    static let border = Theme.textPrimary.opacity(0.16)
    static let accent = Theme.accent
    static let accentWash = Theme.accent.opacity(0.08)
}

/// Settings text button; `filled` draws the accent-wash pill.
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
        Button(action: action) {
            Text(title)
                .font(Theme.subFont)
                .foregroundStyle(color)
                .padding(.horizontal, filled ? 12 : 0)
                .padding(.vertical, filled ? 6 : vPad)
                .background(filled ? Palette.accentWash : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Instrument toggle: rectangular, amber knob when on.
struct InstrumentToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Palette.border, lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn ? Palette.accent : Palette.ink40)
                    .frame(width: 16, height: 15)
                    .padding(3)
            }
            .frame(width: 44, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Segmented selector built from key caps ("Невидим / Индикаторы").
struct WindowSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                let isActive = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(Theme.subFont)
                        .foregroundStyle(isActive ? Palette.accent : Palette.ink60)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .paletteTile(isActive: isActive)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

extension View {
    /// Selectable key-cap chrome: raised fill and an accent ring when active.
    func paletteTile(isActive: Bool) -> some View {
        background(isActive ? Palette.raised : Palette.panel, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isActive ? Palette.accent.opacity(0.5) : Palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
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
        .padding(.vertical, 11)
    }
}

/// Mechanical key cap for hotkey display (⌘ ,).
struct KeyCap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(Theme.mono(11))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Palette.border, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.border)
                    .offset(y: 1)
            )
    }
}
