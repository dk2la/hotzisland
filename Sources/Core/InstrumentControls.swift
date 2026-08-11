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
    var color: Color = Theme.amber
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

/// Mechanical key cap: raised surface, 1px border with a 2px bottom edge.
struct KeyButton: View {
    let label: String
    var isPrimary = false
    var isActive = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.readoutSFont)
                .kerning(0.5)
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .stroke(border, lineWidth: 1)
                )
                .background(
                    // The thicker bottom edge of a physical key.
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .fill(border)
                        .offset(y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }

    private var foreground: Color {
        if isPrimary { return Color(red: 0.043, green: 0.043, blue: 0.039) }
        if isActive { return Theme.amber }
        return Theme.textPrimary.opacity(0.7)
    }

    private var background: Color {
        if isPrimary { return Theme.amber }
        if isActive { return Theme.raisedFill }
        return Theme.raisedFill.opacity(0.75)
    }

    private var border: Color {
        if isPrimary { return .clear }
        if isActive { return Theme.amber.opacity(0.5) }
        return Theme.controlBorder
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
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
