import SwiftUI

/// Welcome: the instrument powers on. One cell per main module lights up
/// in turn — accent flash, LED, icon bounce — while the power meter fills,
/// then the rack holds "ready" and starts over.
struct WelcomeStage: View {
    @State private var lit = 0
    /// The cell that just switched on; its accent ring fades out.
    @State private var flash: Int?

    /// The tour's modules, then "+N" for the rest of the strip.
    private static let cells: [ModuleTab?] = [.calendar, .email, .playbooks, .notes, .assistant, nil]

    private var count: Int { Self.cells.count }

    var body: some View {
        StagePanel(title: OnboardingStep.welcome.panelTitle) {
            BlinkingDot(color: Theme.accent, size: 5)
                .padding(.trailing, 4)
        } content: {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                grid
                meter
                Spacer(minLength: 0)
            }
        }
        .storyboard(finalFrame: { lit = count }, loop: play)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(Self.cells.indices, id: \.self) { index in
                cell(index)
            }
        }
    }

    private func cell(_ index: Int) -> some View {
        let isOn = index < lit
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return VStack(spacing: 9) {
            Image(systemName: Self.cells[index]?.icon ?? "ellipsis")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isOn ? Theme.textPrimary : Theme.textFaint)
                .symbolEffect(.bounce, value: isOn)
                .frame(height: 22)
            Text(label(for: Self.cells[index]).uppercased())
                .font(Theme.labelFont)
                .kerning(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isOn ? Theme.textTertiary : Theme.textFaint)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(shape.fill(isOn ? Theme.raisedFill : Theme.cardFill))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 4, height: 4)
                .shadow(color: Theme.accent.opacity(0.8), radius: 3)
                .padding(8)
                .opacity(isOn ? 1 : 0)
        }
        .overlay(
            shape.stroke(Theme.accent, lineWidth: 1.5)
                .opacity(flash == index ? 1 : 0)
                .animation(.easeOut(duration: flash == index ? 0.05 : 0.7), value: flash)
        )
        .scaleEffect(flash == index ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: flash)
        .animation(.easeOut(duration: 0.25), value: isOn)
    }

    private func label(for tab: ModuleTab?) -> String {
        if let tab { return tab.title }
        let shipping = ModuleTab.allCases.count - ModuleTab.comingSoon.count
        return "+\(shipping - Self.cells.count + 1)"
    }

    /// Power readout: a segmented meter and a mono "lit / total".
    private var meter: some View {
        VStack(spacing: 7) {
            HStack {
                InstrumentLabel("pwr", color: Theme.textQuaternary)
                Spacer(minLength: 0)
                Text(String(format: "%02d/%02d", lit, count))
                    .font(Theme.readoutSFont)
                    .foregroundStyle(lit == count ? Theme.accent : Theme.textTertiary)
            }
            SegmentBar(fraction: Double(lit) / Double(count), segments: 18, height: 3, fillColor: Theme.accent)
        }
        .padding(.horizontal, 2)
    }

    private func play() async -> Bool {
        guard await beat(0.5) else { return false }
        for index in 0..<count {
            lit = index + 1
            flash = index
            guard await beat(0.3) else { return false }
        }
        flash = nil
        guard await beat(3.4) else { return false }
        withAnimation(.easeIn(duration: 0.35)) { lit = 0 }
        return await beat(0.6)
    }
}
