import XCTest
@testable import Recall

final class AccessibilityManagerTests: XCTestCase {
    func testIsAccessibilityTrustedReturnsBool() {
        // Verifies the call compiles and returns a Bool (value depends on system state).
        let trusted = AccessibilityManager.isAccessibilityTrusted()
        XCTAssert(trusted == true || trusted == false)
    }
}
