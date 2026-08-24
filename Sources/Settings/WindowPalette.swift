import SwiftUI

/// Window-surface palette (settings, onboarding). The island is always
/// dark; windows follow the system appearance — rack graphite in dark,
/// Paper in light, with amber darkened to ink for readability.
struct WindowPalette {
    let desk: Color
    let panel: Color
    let raised: Color
    let ink: Color
    let ink60: Color
    let ink40: Color
    let hairline: Color
    let border: Color
    let accent: Color
    let accentWash: Color

    static let rack = WindowPalette(
        desk: Color(red: 0.043, green: 0.043, blue: 0.039),   // #0B0B0A
        panel: Color(red: 0.071, green: 0.071, blue: 0.067),  // #121211
        raised: Color(red: 0.110, green: 0.110, blue: 0.102), // #1C1C1A
        ink: Theme.textPrimary,
        ink60: Theme.textPrimary.opacity(0.6),
        ink40: Theme.textPrimary.opacity(0.4),
        hairline: Theme.textPrimary.opacity(0.09),
        border: Theme.textPrimary.opacity(0.16),
        accent: Theme.accent,
        accentWash: Theme.accent.opacity(0.08)
    )

    /// 10 — Paper: white surfaces, warm desk, amber-ink accent.
    static let paper = WindowPalette(
        desk: Color(red: 0.957, green: 0.953, blue: 0.933),   // #F4F3EE
        panel: .white,
        raised: Color(red: 0.929, green: 0.925, blue: 0.906),
        ink: Color(red: 0.102, green: 0.098, blue: 0.09),
        ink60: Color(red: 0.102, green: 0.098, blue: 0.09).opacity(0.6),
        ink40: Color(red: 0.102, green: 0.098, blue: 0.09).opacity(0.4),
        hairline: Color.black.opacity(0.08),
        border: Color.black.opacity(0.16),
        // Neon green is unreadable on paper — darkened to green-ink.
        accent: Color(red: 0.16, green: 0.52, blue: 0.0),
        accentWash: Color(red: 0.16, green: 0.52, blue: 0.0).opacity(0.08)
    )

    /// V3: windows match the widget and the notch — always the dark rack.
    static func current(_ scheme: ColorScheme) -> WindowPalette {
        .rack
    }
}

/// Instrument toggle: rectangular, amber knob when on.
struct InstrumentToggle: View {
    @Binding var isOn: Bool
    let palette: WindowPalette

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(palette.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(palette.border, lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn ? palette.accent : palette.ink40)
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
    let palette: WindowPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                let isActive = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(Theme.subFont)
                        .foregroundStyle(isActive ? palette.accent : palette.ink60)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(
                            isActive ? palette.raised : palette.panel,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    isActive ? palette.accent.opacity(0.5) : palette.border,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// Settings row: title + explanation on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    let palette: WindowPalette
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.bodyFont)
                    .foregroundStyle(palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.subFont)
                        .foregroundStyle(palette.ink40)
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
    let palette: WindowPalette

    var body: some View {
        Text(symbol)
            .font(Theme.mono(11))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(palette.border, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(palette.border)
                    .offset(y: 1)
            )
    }
}
