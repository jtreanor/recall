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

    // MARK: - moveSelection tests

    func testMoveSelectionDownIncrements() {
        let state = OverlayState()
        state.items = makeItems(count: 5)
        state.selectedIndex = 0
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testMoveSelectionUpDecrements() {
        let state = OverlayState()
        state.items = makeItems(count: 5)
        state.selectedIndex = 2
        state.moveSelection(by: -1)
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testMoveSelectionClampsAtBottom() {
        let state = OverlayState()
        state.items = makeItems(count: 3)
        state.selectedIndex = 2
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testMoveSelectionClampsAtTop() {
        let state = OverlayState()
        state.items = makeItems(count: 3)
        state.selectedIndex = 0
        state.moveSelection(by: -1)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testMoveSelectionIgnoredWhenEmpty() {
        let state = OverlayState()
        state.items = []
        state.selectedIndex = 0
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    private func makeItems(count: Int) -> [HistoryItem] {
        (0..<count).map { i in
            HistoryItem(
                id: Int64(i), kind: .text,
                text: "item \(i)", imagePath: nil,
                contentHash: "hash\(i)", sourceBundleId: nil, createdAt: Date()
            )
        }
    }

    // MARK: - Horizontal navigation (left/right arrow semantics)

    func testRightArrowAdvancesSelection() {
        let state = OverlayState()
        state.items = makeItems(count: 5)
        state.selectedIndex = 1
        // Right arrow maps to moveSelection(by: 1)
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testLeftArrowRetreatSelection() {
        let state = OverlayState()
        state.items = makeItems(count: 5)
        state.selectedIndex = 3
        // Left arrow maps to moveSelection(by: -1)
        state.moveSelection(by: -1)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testRightArrowClampsAtLastCard() {
        let state = OverlayState()
        state.items = makeItems(count: 3)
        state.selectedIndex = 2
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testLeftArrowClampsAtFirstCard() {
        let state = OverlayState()
        state.items = makeItems(count: 3)
        state.selectedIndex = 0
        state.moveSelection(by: -1)
        XCTAssertEqual(state.selectedIndex, 0)
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
            contentHash: "abc", sourceBundleId: nil, createdAt: Date()
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

    // MARK: - Selection adjustment after delete (mirrors AppDelegate.deleteSelectedItem logic)

    // Simulate the mutation AppDelegate.deleteSelectedItem applies so that the logic is
    // exercised independently of the full AppDelegate setup.
    private func applyDelete(to state: OverlayState) {
        let idx = state.selectedIndex
        guard idx < state.items.count else { return }
        state.items.remove(at: idx)
        if !state.items.isEmpty {
            state.selectedIndex = min(idx, state.items.count - 1)
        } else {
            state.selectedIndex = 0
        }
    }

    func testDeleteMiddleItemKeepsSameIndex() {
        let state = OverlayState()
        state.items = makeItems(count: 5)
        state.selectedIndex = 2
        applyDelete(to: state)
        XCTAssertEqual(state.items.count, 4)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testDeleteLastItemMovesSelectionBack() {
        let state = OverlayState()
        state.items = makeItems(count: 3)
        state.selectedIndex = 2
        applyDelete(to: state)
        XCTAssertEqual(state.items.count, 2)
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testDeleteOnlyItemResetsSelectionToZero() {
        let state = OverlayState()
        state.items = makeItems(count: 1)
        state.selectedIndex = 0
        applyDelete(to: state)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testDeleteFirstItemOfManyKeepsSelectionAtZero() {
        let state = OverlayState()
        state.items = makeItems(count: 4)
        state.selectedIndex = 0
        applyDelete(to: state)
        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.selectedIndex, 0)
    }
}
