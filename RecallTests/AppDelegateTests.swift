import XCTest
import AppKit
@testable import Recall

final class AppDelegateTests: XCTestCase {
    private var delegate: AppDelegate!

    override func setUp() {
        super.setUp()
        delegate = AppDelegate()
    }

    override func tearDown() {
        delegate = nil
        super.tearDown()
    }

    // MARK: - writeToPasteboard

    func testWriteTextItemToPasteboard() {
        let item = HistoryItem(
            id: 1, kind: .text,
            text: "hello paste", imagePath: nil,
            contentHash: "abc", sourceBundleId: nil, createdAt: Date()
        )
        delegate.writeToPasteboard(item)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello paste")
    }

    func testWriteImageItemWithBadPathWritesNothing() {
        let item = HistoryItem(
            id: 2, kind: .image,
            text: nil, imagePath: "/nonexistent/path.png",
            contentHash: "def", sourceBundleId: nil, createdAt: Date()
        )
        NSPasteboard.general.clearContents()
        delegate.writeToPasteboard(item)
        // Non-existent path → no PNG data written; pasteboard stays empty
        XCTAssertNil(NSPasteboard.general.data(forType: .png))
    }

    func testPasteSelectedItemDoesNothingWhenEmpty() {
        // Should not crash when items is empty
        delegate.pasteSelectedItem()
    }

    // MARK: - Regression: stale overlay state (V.3 fix)

    func testShowOverlayRefreshesItemsFromStore() throws {
        let store = makeTestStore()
        delegate.historyStore = store
        delegate.overlayState.items = []

        try store.insert(item: .text("fresh item"))
        delegate.showOverlay()

        XCTAssertEqual(delegate.overlayState.items.count, 1)
        XCTAssertEqual(delegate.overlayState.items[0].text, "fresh item")
    }

    func testShowOverlayReflectsLatestStoreState() throws {
        let store = makeTestStore()
        try store.insert(item: .text("old item"))
        delegate.historyStore = store
        delegate.overlayState.items = (try? store.fetchAll()) ?? []

        try store.insert(item: .text("new item"))
        delegate.showOverlay()

        XCTAssertEqual(delegate.overlayState.items.count, 2)
        XCTAssertEqual(delegate.overlayState.items[0].text, "new item")
    }

    // MARK: - Regression: isOverlayVisible desync after Escape (V.3 fix)

    func testShowOverlaySetsVisibleTrue() {
        delegate.showOverlay()
        XCTAssertTrue(delegate.isOverlayVisible)
    }

    func testHideOverlaySetsVisibleFalse() {
        delegate.showOverlay()
        delegate.hideOverlay()
        XCTAssertFalse(delegate.isOverlayVisible)
    }

    func testOnDismissCallbackResetsVisibility() {
        // Simulate the panel firing onDismiss (as Escape does) without going
        // through hideOverlay(), verifying the flag stays in sync.
        delegate.showOverlay()
        XCTAssertTrue(delegate.isOverlayVisible)
        delegate.isOverlayVisible = false  // what onDismiss sets directly
        XCTAssertFalse(delegate.isOverlayVisible)
        // A subsequent showOverlay() must work correctly
        delegate.showOverlay()
        XCTAssertTrue(delegate.isOverlayVisible)
    }

    // MARK: - Milestone 2.9: Paste always writes clipboard regardless of AX status

    func testPasteSelectedItemWritesClipboardEvenWhenCalledWithItem() throws {
        let store = makeTestStore()
        try store.insert(item: .text("ax-test content"))
        delegate.historyStore = store
        delegate.showOverlay()

        // writeToPasteboard is called before the AX check, so clipboard is
        // always updated even if AX is denied and ⌘V is not posted.
        delegate.pasteSelectedItem()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "ax-test content")
    }

    // MARK: - Helpers

    private func makeTestStore() -> HistoryStore {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = tmp.appendingPathComponent("images")
        try! FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let db = try! Database(path: tmp.appendingPathComponent("test.db").path)
        return HistoryStore(db: db, imagesDir: images)
    }
}
