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
            contentHash: "abc", createdAt: Date()
        )
        delegate.writeToPasteboard(item)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello paste")
    }

    func testWriteImageItemWithBadPathWritesNothing() {
        let item = HistoryItem(
            id: 2, kind: .image,
            text: nil, imagePath: "/nonexistent/path.png",
            contentHash: "def", createdAt: Date()
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
}
