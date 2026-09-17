import SwiftUI

/// The island capsule: top corners flare outward (concave arcs continuing the
/// screen edge), bottom corners are regular convex roundings.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// The expanded island as a drop hanging from the notch: a neck exactly as
/// wide as the housing passes through the menu bar, then the body widens
/// into a rounded rectangle below it. The menu bar on both sides of the
/// neck stays uncovered. `neckHeight` is the menu-bar / housing height.
struct NotchDropShape: Shape {
    var neckWidth: CGFloat
    var neckHeight: CGFloat
    var cornerRadius: CGFloat = Theme.windowRadius
    /// Concave fillet where the neck meets the body's top edge.
    var fillet: CGFloat = 12

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(neckWidth, neckHeight) }
        set {
            neckWidth = newValue.first
            neckHeight = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = max(0, rect.height - neckHeight)
        let r = max(0, min(cornerRadius, body / 2, rect.width / 2))
        let f = max(0, min(fillet, r, neckHeight))
        let shoulderY = rect.minY + min(neckHeight, rect.height)
        let neckLeft = rect.midX - neckWidth / 2
        let neckRight = rect.midX + neckWidth / 2

        path.move(to: CGPoint(x: neckLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: rect.minY))
        // Down the neck's right side, flare out onto the body's top edge.
        path.addLine(to: CGPoint(x: neckRight, y: shoulderY - f))
        path.addQuadCurve(to: CGPoint(x: neckRight + f, y: shoulderY), control: CGPoint(x: neckRight, y: shoulderY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: shoulderY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: shoulderY + r), control: CGPoint(x: rect.maxX, y: shoulderY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: shoulderY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: shoulderY), control: CGPoint(x: rect.minX, y: shoulderY))
        path.addLine(to: CGPoint(x: neckLeft - f, y: shoulderY))
        path.addQuadCurve(to: CGPoint(x: neckLeft, y: shoulderY - f), control: CGPoint(x: neckLeft, y: shoulderY))
        path.closeSubpath()
        return path
    }
}
