import SwiftUI

/// Ready: a tiny desktop with the widget docked on it. A cursor grabs the
/// strip by its dots and carries it from edge to edge; the strip turns to
/// lie along each edge and snaps in with a glint, as the real one does.
struct ReadyStage: View {
    @State private var edge: WidgetEdge = .right
    @State private var cursor: CursorSpot?
    @State private var grabbing = false
    @State private var glint: WidgetEdge?

    private static let icons = [OnboardingStep.calendar, .mail, .playbooks, .notes, .assistant].map(\.icon)
    private static let cell: CGFloat = 20
    private static let spacing: CGFloat = 4
    private static let thickness: CGFloat = 28
    private static let grip: CGFloat = 10
    private static let pad: CGFloat = 5
    private static let inset: CGFloat = 6
    private static let menuBar: CGFloat = 14

    /// Where the cursor is, by meaning — resolved against the measured
    /// screen, so the storyboard never needs the layout's numbers.
    private enum CursorSpot: Equatable {
        case rest
        case grip(WidgetEdge)
        case away
    }

    private static var length: CGFloat {
        let count = CGFloat(icons.count)
        return 2 * pad + grip + spacing + count * cell + (count - 1) * spacing
    }

    var body: some View {
        StagePanel(title: OnboardingStep.ready.panelTitle) {
            screen
        }
        .storyboard(finalFrame: { edge = .right }, loop: play)
    }

    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                wallpaper
                menuBarStrip
                edgeGlint(in: size)
                ministrip
                    .position(stripCenter(edge, in: size))
                if let cursor {
                    let point = cursorPoint(cursor, in: size)
                    Image(systemName: grabbing ? "hand.raised.fill" : "hand.point.up.left.fill")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .scaleEffect(grabbing ? 0.88 : 1)
                        .position(x: point.x + 5, y: point.y + 7)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
    }

    /// Graphite with a soft accent bloom — dark enough that the glass reads.
    private var wallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.04, green: 0.04, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 180, height: 180)
                .blur(radius: 50)
                .offset(x: -60, y: 50)
            Circle()
                .fill(StagePalette.blue.opacity(0.35))
                .frame(width: 160, height: 160)
                .blur(radius: 50)
                .offset(x: 80, y: -60)
        }
    }

    private var menuBarStrip: some View {
        HStack(spacing: 6) {
            ForEach([10, 16, 12, 14], id: \.self) { width in
                Capsule().fill(Theme.textPrimary.opacity(0.22)).frame(width: CGFloat(width), height: 3)
            }
            Spacer(minLength: 0)
            Text("9:41")
                .font(Theme.mono(8, .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: Self.menuBar)
        .frame(maxWidth: .infinity)
        .background(Theme.textPrimary.opacity(0.06))
    }

    /// The widget strip at small scale; vertical on the sides, horizontal
    /// on the top and bottom — the same view, so the turn animates.
    private var ministrip: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let layout = edge.isVertical
            ? AnyLayout(VStackLayout(spacing: Self.spacing))
            : AnyLayout(HStackLayout(spacing: Self.spacing))
        let dots = edge.isVertical
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            dots {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Theme.textPrimary.opacity(0.45)).frame(width: 2, height: 2)
                }
            }
            .frame(
                width: edge.isVertical ? Self.cell : Self.grip,
                height: edge.isVertical ? Self.grip : Self.cell
            )
            ForEach(Self.icons.indices, id: \.self) { index in
                Image(systemName: Self.icons[index])
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(index == 0 ? Theme.accent : Theme.textSecondary)
                    .frame(width: Self.cell, height: Self.cell)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index == 0 ? Theme.accentWash : .clear)
                    )
            }
        }
        .padding(edge.isVertical ? .vertical : .horizontal, Self.pad)
        .frame(
            width: edge.isVertical ? Self.thickness : Self.length,
            height: edge.isVertical ? Self.length : Self.thickness
        )
        .background(GlassSurface(shape: shape, dark: true))
        .shadow(color: .black.opacity(grabbing ? 0.5 : 0.25), radius: grabbing ? 8 : 3, y: grabbing ? 4 : 1)
        .scaleEffect(grabbing ? 1.05 : 1)
    }

    /// A brief accent line along the edge the strip just snapped to.
    private func edgeGlint(in size: CGSize) -> some View {
        let horizontal = glint == .top || glint == .bottom
        let frame: CGRect = switch glint {
        case .left: CGRect(x: 0, y: Self.menuBar, width: 2, height: size.height - Self.menuBar)
        case .right: CGRect(x: size.width - 2, y: Self.menuBar, width: 2, height: size.height - Self.menuBar)
        case .top: CGRect(x: 0, y: Self.menuBar, width: size.width, height: 2)
        case .bottom: CGRect(x: 0, y: size.height - 2, width: size.width, height: 2)
        case nil: .zero
        }
        return Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.accent.opacity(0), Theme.accent, Theme.accent.opacity(0)],
                    startPoint: horizontal ? .leading : .top,
                    endPoint: horizontal ? .trailing : .bottom
                )
            )
            .frame(width: frame.width, height: frame.height)
            .shadow(color: Theme.accent.opacity(0.8), radius: 4)
            .offset(x: frame.minX, y: frame.minY)
            .opacity(glint == nil ? 0 : 1)
    }

    private func stripCenter(_ edge: WidgetEdge, in size: CGSize) -> CGPoint {
        let half = Self.thickness / 2 + Self.inset
        let midY = Self.menuBar + (size.height - Self.menuBar) / 2
        return switch edge {
        case .right: CGPoint(x: size.width - half, y: midY)
        case .left: CGPoint(x: half, y: midY)
        case .bottom: CGPoint(x: size.width / 2, y: size.height - half)
        case .top: CGPoint(x: size.width / 2, y: Self.menuBar + half)
        }
    }

    /// The grip dots: the strip's leading end — top on a side, left on a
    /// top or bottom edge.
    private func gripPoint(_ edge: WidgetEdge, in size: CGSize) -> CGPoint {
        let center = stripCenter(edge, in: size)
        let offset = Self.length / 2 - Self.pad - Self.grip / 2
        return edge.isVertical
            ? CGPoint(x: center.x, y: center.y - offset)
            : CGPoint(x: center.x - offset, y: center.y)
    }

    private func cursorPoint(_ spot: CursorSpot, in size: CGSize) -> CGPoint {
        switch spot {
        case .rest: CGPoint(x: size.width * 0.55, y: size.height * 0.7)
        case .grip(let edge): gripPoint(edge, in: size)
        case .away: CGPoint(x: size.width * 0.5, y: size.height * 0.45)
        }
    }

    // MARK: - Storyboard

    private func play() async -> Bool {
        for target in [WidgetEdge.bottom, .left, .right] {
            guard await carry(to: target) else { return false }
        }
        return true
    }

    /// One drag: drift to the dots, grab, carry, release with a glint.
    private func carry(to target: WidgetEdge) async -> Bool {
        if cursor == nil {
            cursor = .rest
        }
        guard await beat(0.5) else { return false }
        withAnimation(.easeInOut(duration: 0.55)) { cursor = .grip(edge) }
        guard await beat(0.6) else { return false }
        withAnimation(.easeOut(duration: 0.12)) { grabbing = true }
        guard await beat(0.18) else { return false }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
            edge = target
            cursor = .grip(target)
        }
        guard await beat(0.6) else { return false }
        withAnimation(.easeOut(duration: 0.15)) { grabbing = false }
        withAnimation(.easeOut(duration: 0.08)) { glint = target }
        guard await beat(0.12) else { return false }
        withAnimation(.easeOut(duration: 0.7)) { glint = nil }
        guard await beat(0.3) else { return false }
        withAnimation(.easeInOut(duration: 0.7)) { cursor = .away }
        return await beat(1.1)
    }
}
