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

    // MARK: - Deactivation behavior

    func testPanelDoesNotHideOnDeactivate() {
        // NSPanel defaults hidesOnDeactivate to true, which lets AppKit order
        // the panel out instantly when Recall deactivates (paste-back activates
        // the previous app before hide()), skipping the close slide and
        // evicting the warm panel.
        let panel = OverlayPanel()
        XCTAssertFalse(panel.hidesOnDeactivate)
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

    // MARK: - Approach O: content-layer slide transform

    func testWarmUpRestsContentTransformAtIdentity() {
        // The window never moves; the slide is a transform on slideView's
        // layer. warmUp() must park that transform at identity (resting) so
        // the next show() starts from a known state.
        let panel = OverlayPanel()
        panel.warmUp()
        let t = panel.slideView.layer?.transform ?? CATransform3DIdentity
        XCTAssertTrue(CATransform3DIsIdentity(t))
    }

    func testShowSettlesContentModelAtIdentityAndAddsSlideAnimation() {
        // show() drives the presentation up from one panel-height below the
        // edge while the model rests at identity, via an explicit
        // CABasicAnimation (immune to activation races) keyed "slide".
        let panel = OverlayPanel()
        panel.show()

        let model = panel.slideView.layer?.transform ?? CATransform3DIdentity
        XCTAssertTrue(CATransform3DIsIdentity(model))
        XCTAssertNotNil(panel.slideView.layer?.animation(forKey: "slide"))

        panel.hide(animated: false)
    }

    func testHideAnimatedSettlesContentModelOffscreen() {
        // The animated close settles the model one panel-height below the edge
        // (m42 == -panelHeight) and drives the presentation down to meet it.
        let panel = OverlayPanel()
        panel.show()
        panel.hide()

        let model = panel.slideView.layer?.transform ?? CATransform3DIdentity
        XCTAssertEqual(model.m42, -OverlayPanel.panelHeight, accuracy: 0.5)
        XCTAssertNotNil(panel.slideView.layer?.animation(forKey: "slide"))

        // Let the slide-out completion (finishHide) run before the next test.
        let expectation = XCTestExpectation(description: "slide-out completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testHideUnanimatedResetsContentTransformToIdentity() {
        // The unanimated path (space switch) goes straight to finishHide ->
        // warmUp, which resets the content transform to identity.
        let panel = OverlayPanel()
        panel.show()
        panel.hide(animated: false)

        let t = panel.slideView.layer?.transform ?? CATransform3DIdentity
        XCTAssertTrue(CATransform3DIsIdentity(t))
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

    // MARK: - Space change dismissal

    func testShowPinsPanelToActiveSpace() {
        let panel = OverlayPanel()
        panel.show()

        // Shown panel must not join all spaces, or it would ride along on a
        // space switch and flash before the dismissal notification arrives
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))

        panel.hide(animated: false)
    }

    func testHideRestoresCanJoinAllSpaces() {
        let panel = OverlayPanel()
        panel.show()
        panel.hide(animated: false)

        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testWarmUpJoinsAllSpaces() {
        let panel = OverlayPanel()
        panel.warmUp()

        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertEqual(panel.alphaValue, 0)
    }

    func testSpaceChangeWhileShownDismissesPanelImmediately() {
        let panel = OverlayPanel()
        var dismissCalled = false
        var hiddenCalled = false
        panel.onDismiss = { dismissCalled = true }
        panel.onHidden = { hiddenCalled = true }
        panel.show()

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )

        // Unanimated path: fully hidden synchronously, no slide-out
        XCTAssertTrue(dismissCalled)
        XCTAssertTrue(hiddenCalled)
        XCTAssertEqual(panel.alphaValue, 0)
    }

    func testSpaceChangeAfterHideDoesNotDismissAgain() {
        let panel = OverlayPanel()
        var dismissCount = 0
        panel.onDismiss = { dismissCount += 1 }
        panel.show()
        panel.hide()
        XCTAssertEqual(dismissCount, 1)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )

        XCTAssertEqual(dismissCount, 1)

        let expectation = XCTestExpectation(description: "slide-out completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
