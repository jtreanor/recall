import XCTest
import SwiftUI
import AppKit
@testable import Recall

final class OverlayViewTests: XCTestCase {

    private func makeStringBinding(_ value: String = "") -> Binding<String> {
        var v = value
        return Binding(get: { v }, set: { v = $0 })
    }

    private func makeBoolBinding(_ value: Bool = false) -> Binding<Bool> {
        var v = value
        return Binding(get: { v }, set: { v = $0 })
    }

    func testOverlayStateStartsEmpty() {
        let state = OverlayState()
        XCTAssertTrue(state.items.isEmpty, "Initial state should be empty — triggers EmptyStateView branch")
    }

    func testOverlayStateNonEmptyAfterItemsSet() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "hello", imagePath: nil,
                        contentHash: "abc", sourceBundleId: nil, createdAt: Date())
        ]
        XCTAssertFalse(state.items.isEmpty, "Non-empty items should trigger card tray branch")
    }

    func testEmptyStateViewInstantiatesWithoutCrash() {
        let view = EmptyStateView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 180)
        XCTAssertNotNil(hosting)
    }

    func testOverlayViewEmptyInstantiatesWithoutCrash() {
        var selectedIndex = 0
        let binding = Binding(get: { selectedIndex }, set: { selectedIndex = $0 })
        let view = OverlayView(items: [], totalItemCount: 0,
                               selectedIndex: binding,
                               searchQuery: makeStringBinding(),
                               isSearchExpanded: makeBoolBinding())
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        XCTAssertNotNil(hosting)
    }

    func testOverlayViewWithItemsInstantiatesWithoutCrash() {
        var selectedIndex = 0
        let binding = Binding(get: { selectedIndex }, set: { selectedIndex = $0 })
        let items = [
            HistoryItem(id: 1, kind: .text, text: "test", imagePath: nil,
                        contentHash: "hash1", sourceBundleId: nil, createdAt: Date())
        ]
        let view = OverlayView(items: items, totalItemCount: items.count,
                               selectedIndex: binding,
                               searchQuery: makeStringBinding(),
                               isSearchExpanded: makeBoolBinding())
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        XCTAssertNotNil(hosting)
    }

    func testOverlayViewAcceptsOnPasteCallback() {
        var selectedIndex = 0
        let binding = Binding(get: { selectedIndex }, set: { selectedIndex = $0 })
        var pasteCalled = false
        let view = OverlayView(items: [], totalItemCount: 0,
                               selectedIndex: binding,
                               searchQuery: makeStringBinding(),
                               isSearchExpanded: makeBoolBinding(),
                               onPaste: { pasteCalled = true })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        XCTAssertNotNil(hosting)
        view.onPaste?()
        XCTAssertTrue(pasteCalled)
    }

    // MARK: - Search filtering

    func testFilteredItemsEmptyQueryReturnsAll() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "hello world", imagePath: nil,
                        contentHash: "a", sourceBundleId: nil, createdAt: Date()),
            HistoryItem(id: 2, kind: .text, text: "foo bar", imagePath: nil,
                        contentHash: "b", sourceBundleId: nil, createdAt: Date())
        ]
        state.searchQuery = ""
        XCTAssertEqual(state.filteredItems.count, 2)
    }

    func testFilteredItemsSubstringMatch() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "hello world", imagePath: nil,
                        contentHash: "a", sourceBundleId: nil, createdAt: Date()),
            HistoryItem(id: 2, kind: .text, text: "foo bar", imagePath: nil,
                        contentHash: "b", sourceBundleId: nil, createdAt: Date())
        ]
        state.searchQuery = "hello"
        XCTAssertEqual(state.filteredItems.count, 1)
        XCTAssertEqual(state.filteredItems.first?.text, "hello world")
    }

    func testFilteredItemsCaseInsensitive() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "Hello World", imagePath: nil,
                        contentHash: "a", sourceBundleId: nil, createdAt: Date())
        ]
        state.searchQuery = "hello"
        XCTAssertEqual(state.filteredItems.count, 1)
    }

    func testFilteredItemsNoMatch() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "hello world", imagePath: nil,
                        contentHash: "a", sourceBundleId: nil, createdAt: Date())
        ]
        state.searchQuery = "xyz"
        XCTAssertEqual(state.filteredItems.count, 0)
    }

    func testFilteredItemsHidesImagesWhenQueryActive() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "hello world", imagePath: nil,
                        contentHash: "a", sourceBundleId: nil, createdAt: Date()),
            HistoryItem(id: 2, kind: .image, text: nil, imagePath: "/tmp/img.png",
                        contentHash: "b", sourceBundleId: nil, createdAt: Date())
        ]
        state.searchQuery = "hello"
        XCTAssertEqual(state.filteredItems.count, 1)
        XCTAssertEqual(state.filteredItems.first?.kind, .text)
    }

    func testFilteredItemsShowsImagesWhenQueryEmpty() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "hello world", imagePath: nil,
                        contentHash: "a", sourceBundleId: nil, createdAt: Date()),
            HistoryItem(id: 2, kind: .image, text: nil, imagePath: "/tmp/img.png",
                        contentHash: "b", sourceBundleId: nil, createdAt: Date())
        ]
        state.searchQuery = ""
        XCTAssertEqual(state.filteredItems.count, 2)
    }

    func testSearchQueryChangeResetsSelectedIndex() {
        let state = OverlayState()
        state.items = [
            HistoryItem(id: 1, kind: .text, text: "hello", imagePath: nil,
                        contentHash: "a", sourceBundleId: nil, createdAt: Date()),
            HistoryItem(id: 2, kind: .text, text: "world", imagePath: nil,
                        contentHash: "b", sourceBundleId: nil, createdAt: Date())
        ]
        state.selectedIndex = 1
        state.searchQuery = "hello"
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testCollapsingSearchClearsQuery() {
        let state = OverlayState()
        state.isSearchExpanded = true
        state.searchQuery = "test"
        state.isSearchExpanded = false
        XCTAssertEqual(state.searchQuery, "")
    }
}
