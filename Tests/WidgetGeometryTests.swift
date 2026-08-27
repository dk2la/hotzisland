import XCTest

/// The minimized strip must stay the same shape and keep exactly one module
/// button — the roll-up reads as the widget folding into itself.
final class WidgetGeometryTests: XCTestCase {
    func testMinimizedKeepsGripPlusOneButton() {
        let full = WidgetGeometry.stripLength(iconCount: 8)
        let mini = WidgetGeometry.stripLength(iconCount: 8, minimized: true)
        let oneIcon = WidgetGeometry.stripLength(iconCount: 1)
        XCTAssertEqual(mini, oneIcon, "minimized shows the first button, nothing else")
        XCTAssertLessThan(mini, full)
    }

    func testMinimizedKeepsFullThickness() {
        // Same width on a side dock: the pill must not get thinner, only
        // shorter, or the collapse reads as a shape change.
        for edge in [WidgetEdge.left, .right] {
            let full = WidgetGeometry.stripSize(iconCount: 6, edge: edge)
            let mini = WidgetGeometry.stripSize(iconCount: 6, edge: edge, minimized: true)
            XCTAssertEqual(mini.width, full.width)
            XCTAssertLessThan(mini.height, full.height)
        }
        for edge in [WidgetEdge.top, .bottom] {
            let full = WidgetGeometry.stripSize(iconCount: 6, edge: edge)
            let mini = WidgetGeometry.stripSize(iconCount: 6, edge: edge, minimized: true)
            XCTAssertEqual(mini.height, full.height)
            XCTAssertLessThan(mini.width, full.width)
        }
    }

    func testSingleTabWidgetDoesNotChangeSize() {
        // Nothing to fold away — the frame must stay put rather than jump.
        XCTAssertEqual(
            WidgetGeometry.stripLength(iconCount: 1, minimized: true),
            WidgetGeometry.stripLength(iconCount: 1)
        )
    }
}
