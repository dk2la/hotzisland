import AppKit

/// Screen edge the widget strip is docked to.
enum WidgetEdge: String, CaseIterable {
    case left
    case right
    case top
    case bottom

    /// Left/right edges lay the icon strip out vertically.
    var isVertical: Bool { self == .left || self == .right }
}

enum WidgetMetrics {
    /// Icon cell side (circular, visionOS ornament) — compact.
    static let cell: CGFloat = 36
    static let spacing: CGFloat = 6
    /// Strip thickness across its axis.
    static let thickness: CGFloat = 44
    /// Gap between the strip and the screen edge.
    static let edgeInset: CGFloat = 6
    /// Gap between the strip and the opened panel.
    static let panelGap: CGFloat = 8
    /// Strip corner radius — squarish, matches the panel language.
    static let radius: CGFloat = 14
    /// Drag-handle dots zone at the strip's leading end.
    static let gripSize: CGFloat = 14
    static let endPadding: CGFloat = 6
    /// Widget panel: user-resizable in both axes — width grip on the outer
    /// edge, height grip on the bottom. Defaults are deliberately compact.
    static let panelMinWidth: CGFloat = 300
    static let panelMaxWidth: CGFloat = 900
    static let panelDefaultWidth: CGFloat = 340
    static let panelMinHeight: CGFloat = 260
    static let panelMaxHeight: CGFloat = 1200
    static let panelDefaultHeight: CGFloat = 360
}

/// Pure frame math for the edge-docked widget. All rects are in Cocoa screen
/// coordinates (y-up) unless named "local" — those are window-local SwiftUI
/// coordinates (y-down, origin at the window's top-left).
enum WidgetGeometry {
    struct ExpandedLayout {
        let window: NSRect
        let stripLocal: CGRect
        let panelLocal: CGRect
    }

    /// Minimized (⌃⌥H): the strip rolls up to its grip plus the first
    /// module button — same shape and thickness, just shorter.
    static func stripLength(iconCount: Int, minimized: Bool = false) -> CGFloat {
        let shown = minimized ? min(iconCount, 1) : iconCount
        let icons = CGFloat(shown) * WidgetMetrics.cell
            + CGFloat(max(0, shown - 1)) * WidgetMetrics.spacing
        return WidgetMetrics.endPadding * 2 + WidgetMetrics.gripSize
            + WidgetMetrics.spacing + icons
    }

    static func stripSize(iconCount: Int, edge: WidgetEdge, minimized: Bool = false) -> CGSize {
        let length = stripLength(iconCount: iconCount, minimized: minimized)
        return edge.isVertical
            ? CGSize(width: WidgetMetrics.thickness, height: length)
            : CGSize(width: length, height: WidgetMetrics.thickness)
    }

    /// Strip rect on screen; `offset` is the normalized 0…1 position of the
    /// strip's center along the edge (survives resolution changes).
    ///
    /// Minimizing keeps the leading edge — the top for a side dock — pinned,
    /// so the widget rolls up into itself instead of sliding along the edge.
    static func stripFrame(
        edge: WidgetEdge,
        offset: Double,
        iconCount: Int,
        minimized: Bool = false,
        on screen: NSScreen
    ) -> NSRect {
        let full = fullStripFrame(edge: edge, offset: offset, iconCount: iconCount, on: screen)
        guard minimized else { return full }
        let size = stripSize(iconCount: iconCount, edge: edge, minimized: true)
        return edge.isVertical
            ? NSRect(x: full.minX, y: full.maxY - size.height, width: size.width, height: size.height)
            : NSRect(x: full.minX, y: full.minY, width: size.width, height: size.height)
    }

    private static func fullStripFrame(
        edge: WidgetEdge,
        offset: Double,
        iconCount: Int,
        on screen: NSScreen
    ) -> NSRect {
        let vf = screen.visibleFrame
        let size = stripSize(iconCount: iconCount, edge: edge)
        let inset = WidgetMetrics.edgeInset
        switch edge {
        case .left:
            return NSRect(
                x: vf.minX + inset,
                y: clampedOrigin(center: vf.minY + offset * vf.height, length: size.height, low: vf.minY, high: vf.maxY),
                width: size.width, height: size.height
            )
        case .right:
            return NSRect(
                x: vf.maxX - inset - size.width,
                y: clampedOrigin(center: vf.minY + offset * vf.height, length: size.height, low: vf.minY, high: vf.maxY),
                width: size.width, height: size.height
            )
        case .bottom:
            return NSRect(
                x: clampedOrigin(center: vf.minX + offset * vf.width, length: size.width, low: vf.minX, high: vf.maxX),
                y: vf.minY + inset,
                width: size.width, height: size.height
            )
        case .top:
            return NSRect(
                x: clampedOrigin(center: vf.minX + offset * vf.width, length: size.width, low: vf.minX, high: vf.maxX),
                y: vf.maxY - inset - size.height,
                width: size.width, height: size.height
            )
        }
    }

    /// Window rect covering strip + panel, plus both rects in window-local
    /// SwiftUI coordinates. The panel opens inward from the edge, centered on
    /// the strip and clamped to the visible frame — the strip never moves.
    static func expandedLayout(
        edge: WidgetEdge,
        offset: Double,
        iconCount: Int,
        panelSize: CGSize,
        on screen: NSScreen
    ) -> ExpandedLayout {
        let vf = screen.visibleFrame
        let strip = stripFrame(edge: edge, offset: offset, iconCount: iconCount, on: screen)
        let gap = WidgetMetrics.panelGap
        let inset = WidgetMetrics.edgeInset

        // Room left for the panel between the strip and the far screen edge.
        let available: CGSize = switch edge {
        case .left: CGSize(width: vf.maxX - strip.maxX - gap - inset, height: vf.height)
        case .right: CGSize(width: strip.minX - gap - vf.minX - inset, height: vf.height)
        case .bottom: CGSize(width: vf.width, height: vf.maxY - strip.maxY - gap - inset)
        case .top: CGSize(width: vf.width, height: strip.minY - gap - vf.minY - inset)
        }
        // Both axes are user-sized, clamped to what the screen leaves. On a
        // side dock the panel stays centered on the strip, so height growth
        // spreads both ways until a screen edge pushes back.
        let size = CGSize(
            width: min(panelSize.width, available.width),
            height: min(panelSize.height, available.height)
        )

        let panel: NSRect = switch edge {
        case .left:
            NSRect(
                x: strip.maxX + gap,
                y: clampedOrigin(center: strip.midY, length: size.height, low: vf.minY, high: vf.maxY),
                width: size.width, height: size.height
            )
        case .right:
            NSRect(
                x: strip.minX - gap - size.width,
                y: clampedOrigin(center: strip.midY, length: size.height, low: vf.minY, high: vf.maxY),
                width: size.width, height: size.height
            )
        case .bottom:
            NSRect(
                x: clampedOrigin(center: strip.midX, length: size.width, low: vf.minX, high: vf.maxX),
                y: strip.maxY + gap,
                width: size.width, height: size.height
            )
        case .top:
            NSRect(
                x: clampedOrigin(center: strip.midX, length: size.width, low: vf.minX, high: vf.maxX),
                y: strip.minY - gap - size.height,
                width: size.width, height: size.height
            )
        }

        let window = strip.union(panel)
        return ExpandedLayout(
            window: window,
            stripLocal: localRect(strip, in: window),
            panelLocal: localRect(panel, in: window)
        )
    }

    /// Nearest edge + normalized offset for a dropped strip frame.
    static func nearestPlacement(for frame: NSRect, on screen: NSScreen) -> (edge: WidgetEdge, offset: Double) {
        let vf = screen.visibleFrame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let distances: [(WidgetEdge, CGFloat)] = [
            (.left, center.x - vf.minX),
            (.right, vf.maxX - center.x),
            (.bottom, center.y - vf.minY),
            (.top, vf.maxY - center.y),
        ]
        let edge = distances.min { $0.1 < $1.1 }!.0
        let offset: Double = edge.isVertical
            ? (center.y - vf.minY) / max(vf.height, 1)
            : (center.x - vf.minX) / max(vf.width, 1)
        return (edge, min(max(offset, 0), 1))
    }

    /// Cocoa screen rect → window-local SwiftUI rect (y flipped).
    private static func localRect(_ rect: NSRect, in window: NSRect) -> CGRect {
        CGRect(
            x: rect.minX - window.minX,
            y: window.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func clampedOrigin(center: CGFloat, length: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        min(max(center - length / 2, low), max(high - length, low))
    }
}
