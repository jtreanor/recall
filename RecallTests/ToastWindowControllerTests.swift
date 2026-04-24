import XCTest
@testable import Recall

final class ToastWindowControllerTests: XCTestCase {
    func testShowDoesNotCrash() {
        let controller = ToastWindowController()
        // show() must not crash even when called outside a normal app run
        controller.show(message: "Test toast", duration: 0.1)
    }

    func testShowTwiceDoesNotCrash() {
        let controller = ToastWindowController()
        controller.show(message: "First", duration: 0.1)
        controller.show(message: "Second", duration: 0.1)
    }
}
