import XCTest
import AppKit
import Combine
@testable import Recall

final class IntegrationTests: XCTestCase {
    var tempDir: URL!
    var store: HistoryStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imagesDir = tempDir.appendingPathComponent("images")
        try! FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let db = try! Database(path: tempDir.appendingPathComponent("test.db").path)
        store = HistoryStore(db: db, imagesDir: imagesDir)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Full cycle

    func testFullCycle_ClipboardChangeFlowsToStore() throws {
        let monitor = ClipboardMonitor()
        var cancellables = Set<AnyCancellable>()
        monitor.itemPublisher
            .sink { [weak self] item in try? self?.store.insert(item: item) }
            .store(in: &cancellables)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("integration cycle test", forType: .string)
        monitor.poll()

        let items = try store.fetchAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].text, "integration cycle test")
        XCTAssertEqual(items[0].kind, .text)
    }

    // MARK: - Deduplication with updated timestamp

    func testDeduplication_SameContentTwice_OneItemWithUpdatedTimestamp() throws {
        // Insert A then B (B is newer, so B is first in fetchAll)
        try store.insert(item: .text("alpha"))
        Thread.sleep(forTimeInterval: 1.1)
        try store.insert(item: .text("beta"))

        let beforeReinsert = try store.fetchAll()
        XCTAssertEqual(beforeReinsert[0].text, "beta")
        XCTAssertEqual(beforeReinsert[1].text, "alpha")

        // Re-insert "alpha" (duplicate). Its updated_at should be bumped, moving it to top.
        Thread.sleep(forTimeInterval: 1.1)
        let dup = try store.insert(item: .text("alpha"))
        XCTAssertNil(dup, "duplicate insert should return nil")

        let items = try store.fetchAll()
        XCTAssertEqual(items.count, 2, "still exactly two items")
        XCTAssertEqual(items[0].text, "alpha", "re-inserted item should now be first (updated_at bumped)")
        XCTAssertEqual(items[1].text, "beta")
    }

    // MARK: - History cap

    func testHistoryCap_501Items_ResultsInExactly500() throws {
        for i in 0..<501 {
            try store.insert(item: .text("item \(i)"))
        }
        let count = try store.count()
        XCTAssertEqual(count, 500)
        let items = try store.fetchAll()
        XCTAssertEqual(items.count, 500)
        // Oldest item (item 0) should have been pruned; newest should be present
        XCTAssertFalse(items.contains { $0.text == "item 0" }, "oldest item should be pruned")
        XCTAssertTrue(items.contains { $0.text == "item 500" }, "newest item should be present")
    }

    // MARK: - Persistence across store close/reopen

    func testPersistence_ItemsSurviveStoreReopenOnDisk() throws {
        try store.insert(item: .text("persist me"))
        try store.insert(item: .text("persist me too"))

        // Simulate closing by releasing and reopening on the same file
        store = nil
        let dbPath = tempDir.appendingPathComponent("test.db").path
        let imagesDir = tempDir.appendingPathComponent("images")
        let db2 = try Database(path: dbPath)
        let store2 = HistoryStore(db: db2, imagesDir: imagesDir)

        let items = try store2.fetchAll()
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.text == "persist me" })
        XCTAssertTrue(items.contains { $0.text == "persist me too" })
    }
}
