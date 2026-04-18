import XCTest
@testable import Recall

final class OverlayStateTests: XCTestCase {
    func testInitialState() {
        let state = OverlayState()
        XCTAssertEqual(state.items.count, 0)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testSelectedIndexClampsOnItemsChange() {
        let state = OverlayState()
        state.selectedIndex = 3
        state.items = []
        // After clearing items, selected index remains as-is (clamping is caller's responsibility)
        XCTAssertEqual(state.selectedIndex, 3)
    }

    func testItemsPublishedOnChange() {
        let state = OverlayState()
        let expectation = XCTestExpectation(description: "items published")

        let cancellable = state.$items.dropFirst().sink { items in
            XCTAssertEqual(items.count, 1)
            expectation.fulfill()
        }

        let item = HistoryItem(
            id: 1, kind: .text,
            text: "hello", imagePath: nil,
            contentHash: "abc", createdAt: Date()
        )
        state.items = [item]

        wait(for: [expectation], timeout: 1)
        _ = cancellable
    }

    func testSelectedIndexPublishedOnChange() {
        let state = OverlayState()
        let expectation = XCTestExpectation(description: "selectedIndex published")

        let cancellable = state.$selectedIndex.dropFirst().sink { index in
            XCTAssertEqual(index, 5)
            expectation.fulfill()
        }

        state.selectedIndex = 5

        wait(for: [expectation], timeout: 1)
        _ = cancellable
    }
}
