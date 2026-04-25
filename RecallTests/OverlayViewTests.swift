import XCTest
import SwiftUI
import AppKit
@testable import Recall

final class OverlayViewTests: XCTestCase {

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
        let view = OverlayView(items: [], selectedIndex: binding)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 180)
        XCTAssertNotNil(hosting)
    }

    func testOverlayViewWithItemsInstantiatesWithoutCrash() {
        var selectedIndex = 0
        let binding = Binding(get: { selectedIndex }, set: { selectedIndex = $0 })
        let items = [
            HistoryItem(id: 1, kind: .text, text: "test", imagePath: nil,
                        contentHash: "hash1", sourceBundleId: nil, createdAt: Date())
        ]
        let view = OverlayView(items: items, selectedIndex: binding)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 180)
        XCTAssertNotNil(hosting)
    }

    func testOverlayViewAcceptsOnPasteCallback() {
        var selectedIndex = 0
        let binding = Binding(get: { selectedIndex }, set: { selectedIndex = $0 })
        var pasteCalled = false
        let view = OverlayView(items: [], selectedIndex: binding, onPaste: { pasteCalled = true })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 180)
        XCTAssertNotNil(hosting)
        // Confirm the callback closure is retained and callable
        view.onPaste?()
        XCTAssertTrue(pasteCalled)
    }
}
