import XCTest
import AppKit
import Combine
@testable import Recall

final class FileHandlingTests: XCTestCase {
    var store: HistoryStore!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imagesDir = tempDir.appendingPathComponent("images")
        try! FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let db = try! Database(path: tempDir.appendingPathComponent("test.db").path)
        let suiteName = "FileHandlingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(500, forKey: "historyLimit")
        store = HistoryStore(db: db, imagesDir: imagesDir, settings: SettingsManager(defaults: defaults))
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - ClipboardItem model

    func testFileClipboardItemCarriesPaths() {
        let url1 = URL(fileURLWithPath: "/tmp/alpha.txt")
        let url2 = URL(fileURLWithPath: "/tmp/beta.pdf")
        let item = ClipboardItem.file(paths: [url1, url2])
        guard case .file(let paths) = item else { return XCTFail("expected .file") }
        XCTAssertEqual(paths.count, 2)
        XCTAssertEqual(paths[0].path, "/tmp/alpha.txt")
        XCTAssertEqual(paths[1].path, "/tmp/beta.pdf")
    }

    // MARK: - HistoryStore insert + fetch round-trip

    func testSingleFileInsertAndFetch() throws {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        let inserted = try XCTUnwrap(store.insert(item: .file(paths: [url])))

        XCTAssertEqual(inserted.kind, .file)
        XCTAssertEqual(inserted.filePaths, ["/tmp/report.pdf"])
        XCTAssertEqual(inserted.text, "report.pdf")

        let fetched = try XCTUnwrap(try store.fetchAll().first)
        XCTAssertEqual(fetched.kind, .file)
        XCTAssertEqual(fetched.filePaths, ["/tmp/report.pdf"])
        XCTAssertEqual(fetched.text, "report.pdf")
    }

    func testMultiFileInsertAndFetch() throws {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
            URL(fileURLWithPath: "/tmp/c.txt")
        ]
        let inserted = try XCTUnwrap(store.insert(item: .file(paths: urls)))

        XCTAssertEqual(inserted.filePaths?.count, 3)
        // display name mentions first file (sorted) + count
        let displayName = try XCTUnwrap(inserted.text)
        XCTAssertTrue(displayName.contains("+2"), "expected '+2' in '\(displayName)'")

        let fetched = try XCTUnwrap(try store.fetchAll().first)
        XCTAssertEqual(fetched.filePaths?.count, 3)
    }

    // MARK: - Deduplication

    func testSameFileSetDeduplicated() throws {
        let urls = [URL(fileURLWithPath: "/tmp/x.png"), URL(fileURLWithPath: "/tmp/y.png")]
        try store.insert(item: .file(paths: urls))
        try store.insert(item: .file(paths: urls))

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
    }

    func testFileOrderInsensitiveDeduplication() throws {
        let urlA = URL(fileURLWithPath: "/tmp/a.txt")
        let urlB = URL(fileURLWithPath: "/tmp/b.txt")
        try store.insert(item: .file(paths: [urlA, urlB]))
        try store.insert(item: .file(paths: [urlB, urlA])) // reversed order
        XCTAssertEqual(try store.fetchAll().count, 1)
    }

    // MARK: - fileDisplayName

    func testFileDisplayNameSingleFile() {
        let item = HistoryItem(
            id: 1, kind: .file, text: "document.pdf", imagePath: nil,
            contentHash: "h", sourceBundleId: nil, createdAt: Date(),
            filePaths: ["/home/user/document.pdf"]
        )
        XCTAssertEqual(item.fileDisplayName, "document.pdf")
    }

    func testFileDisplayNameMultiFile() {
        let item = HistoryItem(
            id: 1, kind: .file, text: "a.txt  +2", imagePath: nil,
            contentHash: "h", sourceBundleId: nil, createdAt: Date(),
            filePaths: ["/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt"]
        )
        let name = item.fileDisplayName ?? ""
        XCTAssertTrue(name.contains("+2"), "expected '+2' in '\(name)'")
    }

    // MARK: - writeToPasteboard

    func testWriteToPasteboardWritesFileURLs() throws {
        // Create real temp files so FileManager.fileExists passes.
        let fileA = tempDir.appendingPathComponent("test_a.txt")
        let fileB = tempDir.appendingPathComponent("test_b.txt")
        try "aaa".write(to: fileA, atomically: true, encoding: .utf8)
        try "bbb".write(to: fileB, atomically: true, encoding: .utf8)

        let item = HistoryItem(
            id: 1, kind: .file, text: "test_a.txt  +1", imagePath: nil,
            contentHash: "h", sourceBundleId: nil, createdAt: Date(),
            filePaths: [fileA.path, fileB.path]
        )
        AppDelegate().writeToPasteboard(item)

        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(urls?.count, 2)
    }

    func testWriteToPasteboardFallsBackToStringWhenFilesGone() {
        let item = HistoryItem(
            id: 1, kind: .file, text: "gone.txt", imagePath: nil,
            contentHash: "h", sourceBundleId: nil, createdAt: Date(),
            filePaths: ["/nonexistent/path/gone.txt"]
        )
        AppDelegate().writeToPasteboard(item)

        let str = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(str, "/nonexistent/path/gone.txt")
    }

    // MARK: - ClipboardMonitor file detection

    func testMonitorDetectsFileURL() throws {
        let fileURL = tempDir.appendingPathComponent("monitor_test.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let monitor = ClipboardMonitor()
        var cancellables = Set<AnyCancellable>()
        let exp = expectation(description: "file item emitted")
        var received: CapturedItem?

        monitor.itemPublisher.sink { item in
            received = item
            exp.fulfill()
        }.store(in: &cancellables)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([fileURL as NSURL])
        monitor.poll()

        wait(for: [exp], timeout: 1)
        guard case .file(let paths) = received?.item else {
            return XCTFail("expected .file, got \(String(describing: received?.item))")
        }
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].path, fileURL.path)
    }

    func testMonitorDetectsMultipleFileURLs() throws {
        let fileA = tempDir.appendingPathComponent("ma.txt")
        let fileB = tempDir.appendingPathComponent("mb.txt")
        try "a".write(to: fileA, atomically: true, encoding: .utf8)
        try "b".write(to: fileB, atomically: true, encoding: .utf8)

        let monitor = ClipboardMonitor()
        var cancellables = Set<AnyCancellable>()
        let exp = expectation(description: "file item emitted")
        var received: CapturedItem?

        monitor.itemPublisher.sink { item in
            received = item
            exp.fulfill()
        }.store(in: &cancellables)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([fileA as NSURL, fileB as NSURL])
        monitor.poll()

        wait(for: [exp], timeout: 1)
        guard case .file(let paths) = received?.item else {
            return XCTFail("expected .file")
        }
        XCTAssertEqual(paths.count, 2)
    }

    // MARK: - Search filter

    func testFileItemsMatchedByFilename() throws {
        let url = URL(fileURLWithPath: "/Users/james/Documents/quarterly_report.pdf")
        try store.insert(item: .file(paths: [url]))

        let state = OverlayState()
        state.items = try store.fetchAll()
        state.searchQuery = "quarterly"
        state.isSearchExpanded = true

        XCTAssertEqual(state.filteredItems.count, 1)
        XCTAssertEqual(state.filteredItems[0].kind, .file)
    }

    func testFileItemsNotMatchedByUnrelatedQuery() throws {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        try store.insert(item: .file(paths: [url]))

        let state = OverlayState()
        state.items = try store.fetchAll()
        state.searchQuery = "zzznomatch"
        state.isSearchExpanded = true

        XCTAssertEqual(state.filteredItems.count, 0)
    }
}
