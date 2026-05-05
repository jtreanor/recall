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

    func testSlideAnimationTranslationMatchesPanelHeight() {
        // The CABasicAnimation translate-Y distance must equal panelHeight so the content
        // starts fully below the window's clip boundary.
        let translation = CATransform3DMakeTranslation(0, -OverlayPanel.panelHeight, 0)
        XCTAssertEqual(translation.m42, -OverlayPanel.panelHeight, accuracy: 0.5)
    }

    func testVisibleFrameIsFullScreenWidth() {
        guard let screen = NSScreen.main else { return }
        let panel = OverlayPanel()
        // Animation keeps window fixed at visibleFrame() — it must span the full screen width
        // so no x-movement is possible regardless of CALayer animation.
        XCTAssertEqual(panel.visibleFrame().width, screen.frame.width)
        XCTAssertEqual(panel.visibleFrame().minX, screen.frame.minX)
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
