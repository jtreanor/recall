import XCTest
import AppKit
import Combine
@testable import Recall

final class RichTextTests: XCTestCase {
    var store: HistoryStore!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imagesDir = tempDir.appendingPathComponent("images")
        try! FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let db = try! Database(path: tempDir.appendingPathComponent("test.db").path)
        let suiteName = "RichTextTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(500, forKey: "historyLimit")
        store = HistoryStore(db: db, imagesDir: imagesDir, settings: SettingsManager(defaults: defaults))
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: "pasteAsPlainText")
        super.tearDown()
    }

    // MARK: - ClipboardItem model

    func testClipboardItemCarriesRTF() {
        let rtf = makeRTF("bold text")
        let item = ClipboardItem.text("bold text", rtf: rtf)
        guard case .text(let s, let r) = item else { return XCTFail("expected .text") }
        XCTAssertEqual(s, "bold text")
        XCTAssertNotNil(r)
    }

    func testClipboardItemWithNoRTF() {
        let item = ClipboardItem.text("plain", rtf: nil)
        guard case .text(_, let r) = item else { return XCTFail("expected .text") }
        XCTAssertNil(r)
    }

    // MARK: - Round-trip: insert then fetch

    func testRTFRoundTrip() throws {
        let rtf = makeRTF("Hello World")
        let inserted = try XCTUnwrap(store.insert(item: .text("Hello World", rtf: rtf)))
        XCTAssertEqual(inserted.rtfData, rtf)

        let fetched = try XCTUnwrap(try store.fetchAll().first)
        XCTAssertEqual(fetched.rtfData, rtf)
    }

    func testPlainTextItemHasNoRTF() throws {
        try store.insert(item: .text("plain only", rtf: nil))
        let fetched = try XCTUnwrap(try store.fetchAll().first)
        XCTAssertNil(fetched.rtfData)
    }

    // MARK: - writeToPasteboard

    func testWriteToPasteboardWritesRTFWhenAvailable() {
        let rtf = makeRTF("rich")
        let item = HistoryItem(
            id: 1, kind: .text, text: "rich", imagePath: nil, rtfData: rtf,
            contentHash: "abc", sourceBundleId: nil, createdAt: Date()
        )
        UserDefaults.standard.set(false, forKey: "pasteAsPlainText")

        AppDelegate().writeToPasteboard(item)

        XCTAssertNotNil(NSPasteboard.general.data(forType: .rtf))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "rich")
    }

    func testWriteToPasteboardSkipsRTFWhenPlainTextOnly() {
        let rtf = makeRTF("rich")
        let item = HistoryItem(
            id: 1, kind: .text, text: "rich", imagePath: nil, rtfData: rtf,
            contentHash: "abc", sourceBundleId: nil, createdAt: Date()
        )
        UserDefaults.standard.set(true, forKey: "pasteAsPlainText")

        AppDelegate().writeToPasteboard(item)

        XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "rich")
    }

    func testWriteToPasteboardFallsBackToPlainTextWhenNoRTF() {
        let item = HistoryItem(
            id: 1, kind: .text, text: "plain", imagePath: nil, rtfData: nil,
            contentHash: "abc", sourceBundleId: nil, createdAt: Date()
        )
        UserDefaults.standard.set(false, forKey: "pasteAsPlainText")

        AppDelegate().writeToPasteboard(item)

        XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "plain")
    }

    // MARK: - pasteAsPlainText setting

    func testPasteAsPlainTextDefaultsFalse() {
        let suiteName = "RichTextTests.setting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsManager(defaults: defaults)
        XCTAssertFalse(settings.pasteAsPlainText)
    }

    func testPasteAsPlainTextPersists() {
        let suiteName = "RichTextTests.setting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsManager(defaults: defaults)
        settings.pasteAsPlainText = true
        XCTAssertTrue(settings.pasteAsPlainText)
        settings.pasteAsPlainText = false
        XCTAssertFalse(settings.pasteAsPlainText)
    }

    // MARK: - ClipboardMonitor RTF poll

    func testMonitorCapturesRTFFromPasteboard() {
        let monitor = ClipboardMonitor()
        var cancellables = Set<AnyCancellable>()
        let exp = expectation(description: "item emitted")
        var received: CapturedItem?

        monitor.itemPublisher.sink { item in
            received = item
            exp.fulfill()
        }.store(in: &cancellables)

        let rtf = makeRTF("formatted")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(rtf, forType: .rtf)
        NSPasteboard.general.setString("formatted", forType: .string)
        monitor.poll()

        wait(for: [exp], timeout: 1)
        guard case .text(_, let r) = received?.item else { return XCTFail("expected .text") }
        XCTAssertNotNil(r)
    }

    func testMonitorProducesNilRTFWhenNotOnPasteboard() {
        let monitor = ClipboardMonitor()
        var cancellables = Set<AnyCancellable>()
        let exp = expectation(description: "item emitted")
        var received: CapturedItem?

        monitor.itemPublisher.sink { item in
            received = item
            exp.fulfill()
        }.store(in: &cancellables)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("no-rtf-\(UUID())", forType: .string)
        monitor.poll()

        wait(for: [exp], timeout: 1)
        guard case .text(_, let r) = received?.item else { return XCTFail("expected .text") }
        XCTAssertNil(r)
    }

    // MARK: - Helpers

    private func makeRTF(_ text: String) -> Data {
        let attrStr = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        )
        return (try? attrStr.data(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }
}
