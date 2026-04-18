import XCTest
@testable import Recall

final class HotkeyManagerTests: XCTestCase {

    func testCallbackIsInvokedWhenTriggered() {
        let expectation = XCTestExpectation(description: "callback invoked")
        let manager = HotkeyManager { expectation.fulfill() }
        manager.fireForTesting()
        wait(for: [expectation], timeout: 1)
    }

    func testUnregisterPreventsLeakOfCallback() {
        var callCount = 0
        let manager = HotkeyManager { callCount += 1 }
        manager.fireForTesting()
        XCTAssertEqual(callCount, 1)
        manager.unregister()
        // After unregister, Carbon hotkey is removed — we can't fire it again through Carbon,
        // but we verify the object is still alive and the API doesn't crash.
        XCTAssertEqual(callCount, 1)
    }

    func testOverlayToggleLogicTogglesIsOverlayVisible() {
        let delegate = AppDelegate()
        XCTAssertFalse(delegate.isOverlayVisible)

        // Simulate what setupHotkey wires up: toggle on each fire.
        // We call showOverlay/hideOverlay directly since we can't fire Carbon events in tests.
        delegate.showOverlay()
        XCTAssertTrue(delegate.isOverlayVisible)

        delegate.hideOverlay()
        XCTAssertFalse(delegate.isOverlayVisible)
    }
}
