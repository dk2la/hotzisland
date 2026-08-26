import SwiftUI

/// Press feedback: subtle scale + dim, 120ms ease-out.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Instrument caption: mono uppercase with tracking (CPU · MEM · REC).
struct InstrumentLabel: View {
    let text: String
    var color: Color = Theme.textQuaternary

    init(_ text: String, color: Color = Theme.textQuaternary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.labelFont)
            .kerning(1.2)
            .foregroundStyle(color)
    }
}

/// Blinking indicator dot — the only permitted "animation of data":
/// hardware-style 2s pulse.
struct BlinkingDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 6
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.2 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

/// Discrete segmented meter — reads better peripherally than a smooth bar.
/// Values jump; no animation by design.
struct SegmentBar: View {
    let fraction: Double
    var segments = 10
    var height: CGFloat = 3
    /// nil → severity coloring (white → amber → red).
    var fillColor: Color?

    var body: some View {
        let filled = Int((max(0, min(1, fraction)) * Double(segments)).rounded())
        let color = fillColor ?? Theme.severity(fraction)
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? color : Theme.segmentOff)
                    .frame(height: height)
            }
        }
    }
}

/// V3 key: glass capsule. Primary is a solid white surface with a dark
/// label; active keeps a bright ring on raised glass.
struct KeyButton: View {
    let label: String
    var isPrimary = false
    var isActive = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: isPrimary ? .semibold : .medium))
                .kerning(0.3)
                .foregroundStyle(foreground)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(background, in: Capsule())
                .overlay(Capsule().stroke(border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }

    private var foreground: Color {
        if isPrimary { return Theme.inkOnAccent }
        if isActive { return Theme.textPrimary }
        return Theme.textPrimary.opacity(0.7)
    }

    private var background: Color {
        if isPrimary { return Theme.accent }
        if isActive { return Theme.raisedFill }
        return Theme.raisedFill.opacity(0.75)
    }

    private var border: Color {
        if isPrimary { return .clear }
        if isActive { return Theme.accentBorder }
        return .clear
    }
}

/// 1px separator line.
struct Hairline: View {
    var color: Color = Theme.hairlineSoft

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

/// Dashed outline area: empty states and drop zones ("no signal").
struct DashedZone: View {
    let label: String
    var sublabel: String?

    var body: some View {
        VStack(spacing: 6) {
            InstrumentLabel(label, color: Theme.textPrimary.opacity(0.45))
            if let sublabel {
                Text(sublabel)
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
        )
    }
}

/// Data-register row: mono column on the left, prose in the middle, mono
/// annotation on the right.
struct DataRow<Trailing: View>: View {
    let leading: String
    let title: String
    var titleColor: Color = Theme.textPrimary
    var leadingWidth: CGFloat = 44
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(leading)
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.textFaint)
                .frame(width: leadingWidth, alignment: .leading)
            Text(title)
                .font(Theme.bodyFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(titleColor)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 10)
    }
}

/// Themed shell for any island surface — the three treatments of the notch.
/// Glass is the V3 dark-glass recipe (system blur + black tint); Glow tints
/// its ring with the artwork's average color.
struct InstrumentShell<S: Shape>: View {
    let shape: S
    let theme: IslandTheme
    var accent: Color?

    var body: some View {
        switch theme {
        case .stealth:
            shape.fill(Theme.islandFill)
        case .glass:
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Theme.glassTintDark))
        case .glow:
            let ring = accent ?? Theme.textQuaternary
            shape.fill(Theme.islandFill)
                .overlay(shape.stroke(ring.opacity(0.9), lineWidth: 1).blur(radius: 2.5))
                .overlay(shape.stroke(ring.opacity(0.7), lineWidth: 1))
        }
    }
}

/// Empty state for a module that needs an account configured: dashed zone
/// plus one primary button that deep-links to Settings → Accounts.
struct ModuleSetupPrompt: View {
    let title: String
    let sublabel: String

    var body: some View {
        VStack(spacing: 12) {
            DashedZone(label: title, sublabel: sublabel)
                .frame(maxHeight: 110)
            GlassCapsuleButton(label: L10n.t(.mailSetupAction), isPrimary: true) {
                NotificationCenter.default.post(
                    name: .hotzOpenSettings,
                    object: nil,
                    userInfo: ["page": SettingsView.Page.accounts.rawValue]
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
