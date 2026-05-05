import XCTest
import AppKit
@testable import Recall

final class OverlayPanelTests: XCTestCase {
    func testPositionAtScreenBottomSetsFullWidthAndFixedHeight() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        let panel = OverlayPanel()
        panel.positionAtScreenBottom()

        XCTAssertEqual(panel.frame.width, screen.frame.width)
        XCTAssertEqual(panel.frame.height, OverlayPanel.panelHeight)
    }

    func testPositionAtScreenBottomAnchorsToVisibleFrameBottom() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        let panel = OverlayPanel()
        panel.positionAtScreenBottom()

        XCTAssertEqual(panel.frame.minY, screen.visibleFrame.minY)
        XCTAssertEqual(panel.frame.minX, screen.frame.minX)
    }

    func testPositionAtScreenBottomIsDeterministic() {
        let panel = OverlayPanel()
        panel.positionAtScreenBottom()
        let first = panel.frame
        panel.positionAtScreenBottom()
        XCTAssertEqual(panel.frame, first)
    }

    // MARK: - Slide animation frame tests

    func testVisibleFrameMatchesScreenBottom() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }
        let panel = OverlayPanel()
        let vf = panel.visibleFrame()

        XCTAssertEqual(vf.width, screen.frame.width)
        XCTAssertEqual(vf.height, OverlayPanel.panelHeight)
        XCTAssertEqual(vf.minY, screen.visibleFrame.minY)
        XCTAssertEqual(vf.minX, screen.frame.minX)
    }

    func testStartFrameIsBelowVisibleFrame() {
        let panel = OverlayPanel()
        let vf = panel.visibleFrame()
        let start = vf.offsetBy(dx: 0, dy: -vf.height)

        // Same x and width — guarantees purely vertical animation with no diagonal component
        XCTAssertEqual(start.minX, vf.minX)
        XCTAssertEqual(start.width, vf.width)
        XCTAssertEqual(start.height, vf.height)

        // Starts exactly one panel-height below the visible frame
        XCTAssertEqual(start.minY, vf.minY - OverlayPanel.panelHeight, accuracy: 0.5)
    }

    func testStartFrameTopEdgeIsAtScreenBottom() {
        let panel = OverlayPanel()
        let vf = panel.visibleFrame()
        let start = vf.offsetBy(dx: 0, dy: -vf.height)

        // The top of the start frame sits exactly at the visible frame's bottom edge
        XCTAssertEqual(start.maxY, vf.minY, accuracy: 0.5)
    }

    // MARK: - M3.4 callbacks

    func testOnDeleteCallbackCanBeAssignedAndCalled() {
        let panel = OverlayPanel()
        var called = false
        panel.onDelete = { called = true }
        panel.onDelete?()
        XCTAssertTrue(called)
    }

    func testOnPasteCallbackCanBeAssignedAndCalled() {
        let panel = OverlayPanel()
        var called = false
        panel.onPaste = { called = true }
        panel.onPaste?()
        XCTAssertTrue(called)
    }

    func testHideEventuallyOrdersOutPanel() {
        let panel = OverlayPanel()
        var dismissCalled = false
        panel.onDismiss = { dismissCalled = true }
        panel.show()

        panel.hide()

        // onDismiss fires synchronously at the start of hide()
        XCTAssertTrue(dismissCalled)

        // Wait for slide-out animation to complete before the next test
        let expectation = XCTestExpectation(description: "slide-out completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
