import SwiftUI

/// The last page: the card is a desktop. A cursor grabs the widget's strip
/// by its dots and carries it from edge to edge; the strip turns to lie
/// along each edge and snaps in with a glint, as the real one does. The
/// three shortcuts worth knowing float in the middle.
struct ReadyScene: View {
    /// The card's widget scale, so the strip matches the other pages.
    let scale: CGFloat
    /// The shortcuts as the user has them bound.
    var hotkeys: HotkeyService

    @State private var edge: WidgetEdge = .right
    @State private var cursor: CursorSpot?
    @State private var grabbing = false
    @State private var glint: WidgetEdge?

    /// Where the cursor is, by meaning — resolved against the measured
    /// card, so the storyboard never needs the layout's numbers.
    private enum CursorSpot: Equatable {
        case rest
        case grip(WidgetEdge)
        case away
    }

    private static let inset: CGFloat = 12
    private static let menuBar: CGFloat = 22

    private var length: CGFloat {
        WidgetGeometry.stripLength(iconCount: MiniWidget.tabs.count) * scale
    }

    private var thickness: CGFloat { WidgetMetrics.thickness * scale }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                menuBarStrip
                shortcutsSheet
                    .position(x: size.width / 2, y: Self.menuBar + (size.height - Self.menuBar) / 2)
                edgeGlint(in: size)
                MiniStrip(tabs: MiniWidget.tabs, active: .calendar, vertical: edge.isVertical)
                    .scaleEffect(scale * (grabbing ? 1.05 : 1))
                    .shadow(color: .black.opacity(grabbing ? 0.45 : 0.25), radius: grabbing ? 12 : 5, y: grabbing ? 6 : 2)
                    .position(stripCenter(edge, in: size))
                if let cursor {
                    let point = cursorPoint(cursor, in: size)
                    Image(systemName: grabbing ? "hand.raised.fill" : "hand.point.up.left.fill")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .scaleEffect(grabbing ? 0.88 : 1)
                        .position(x: point.x + 6, y: point.y + 8)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .storyboard(finalFrame: { edge = .right }, loop: play)
    }

    /// A faint menu bar: what makes the card read as a screen.
    private var menuBarStrip: some View {
        HStack(spacing: 8) {
            ForEach([12, 22, 16, 18, 14], id: \.self) { width in
                Capsule()
                    .fill(Theme.textPrimary.opacity(0.35))
                    .frame(width: CGFloat(width), height: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.menuBar)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08))
    }

    /// The day-one shortcuts on a small glass sheet.
    private var shortcutsSheet: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            row(hotkeys.combo(for: .toggleWidgetHidden).keyCaps, L10n.t(.setHideWidget))
            row(hotkeys.combo(for: .togglePanelPin).keyCaps, L10n.t(.setPinPanel))
            row(hotkeys.combo(for: .toggleSettings).keyCaps, L10n.t(.setOpenSettings))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(GlassSurface(shape: shape, dark: true))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }

    private func row(_ caps: [String], _ title: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(caps, id: \.self) { KeyCap(symbol: $0) }
            }
            .frame(minWidth: 78, alignment: .leading)
            Text(title)
                .font(Theme.subFont)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    /// A brief accent line along the edge the strip just snapped to.
    private func edgeGlint(in size: CGSize) -> some View {
        let horizontal = glint == .top || glint == .bottom
        let frame: CGRect = switch glint {
        case .left: CGRect(x: 0, y: Self.menuBar, width: 3, height: size.height - Self.menuBar)
        case .right: CGRect(x: size.width - 3, y: Self.menuBar, width: 3, height: size.height - Self.menuBar)
        case .top: CGRect(x: 0, y: Self.menuBar, width: size.width, height: 3)
        case .bottom: CGRect(x: 0, y: size.height - 3, width: size.width, height: 3)
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
            .shadow(color: Theme.accent.opacity(0.9), radius: 6)
            .offset(x: frame.minX, y: frame.minY)
            .opacity(glint == nil ? 0 : 1)
    }

    private func stripCenter(_ edge: WidgetEdge, in size: CGSize) -> CGPoint {
        let half = thickness / 2 + Self.inset
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
        let offset = length / 2 - (WidgetMetrics.endPadding + WidgetMetrics.gripSize / 2) * scale
        return edge.isVertical
            ? CGPoint(x: center.x, y: center.y - offset)
            : CGPoint(x: center.x - offset, y: center.y)
    }

    private func cursorPoint(_ spot: CursorSpot, in size: CGSize) -> CGPoint {
        switch spot {
        case .rest: CGPoint(x: size.width * 0.72, y: size.height * 0.8)
        case .grip(let edge): gripPoint(edge, in: size)
        case .away: CGPoint(x: size.width * 0.76, y: size.height * 0.62)
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
            withAnimation(.easeOut(duration: 0.3)) { cursor = .rest }
        }
        guard await beat(0.6) else { return false }
        withAnimation(.easeInOut(duration: 0.6)) { cursor = .grip(edge) }
        guard await beat(0.65) else { return false }
        withAnimation(.easeOut(duration: 0.12)) { grabbing = true }
        guard await beat(0.18) else { return false }
        withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
            edge = target
            cursor = .grip(target)
        }
        guard await beat(0.65) else { return false }
        withAnimation(.easeOut(duration: 0.15)) { grabbing = false }
        withAnimation(.easeOut(duration: 0.08)) { glint = target }
        guard await beat(0.12) else { return false }
        withAnimation(.easeOut(duration: 0.8)) { glint = nil }
        guard await beat(0.3) else { return false }
        withAnimation(.easeInOut(duration: 0.7)) { cursor = .away }
        return await beat(1.2)
    }
}
