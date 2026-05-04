import XCTest
@testable import Recall

final class URLDetectionTests: XCTestCase {

    // MARK: - detectFirstURL accuracy

    func testDetectsPlainHTTPSURL() {
        XCTAssertNotNil(detectFirstURL(in: "https://github.com/jtreanor/recall"))
    }

    func testDetectsHTTPURL() {
        XCTAssertNotNil(detectFirstURL(in: "http://example.com"))
    }

    func testDetectsURLMidSentence() {
        XCTAssertNotNil(detectFirstURL(in: "Check out https://apple.com for more info."))
    }

    func testDetectsURLAtEndOfSentence() {
        XCTAssertNotNil(detectFirstURL(in: "Visit https://swift.org."))
    }

    func testDoesNotDetectPlainText() {
        XCTAssertNil(detectFirstURL(in: "This is just plain text with no URL"))
    }

    func testDoesNotDetectCodeWithoutURL() {
        XCTAssertNil(detectFirstURL(in: "func hello() -> String { return \"world\" }"))
    }

    func testExtractsCorrectHost() {
        let url = detectFirstURL(in: "https://github.com/jtreanor")
        XCTAssertEqual(url?.host, "github.com")
    }

    func testExtractsCorrectHostFromMidSentence() {
        let url = detectFirstURL(in: "See https://swift.org/documentation for details")
        XCTAssertEqual(url?.host, "swift.org")
    }

    func testReturnsFirstURLWhenMultiplePresent() {
        let url = detectFirstURL(in: "Visit https://apple.com or https://google.com")
        XCTAssertEqual(url?.host, "apple.com")
    }

    // MARK: - HistoryItem.detectedURL via HistoryStore

    func testInsertedURLItemHasDetectedURL() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.insert(item: .text("https://apple.com", rtf: nil)))
        XCTAssertNotNil(item.detectedURL)
        XCTAssertEqual(item.detectedURL?.host, "apple.com")
    }

    func testInsertedPlainTextHasNoDetectedURL() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.insert(item: .text("just plain text", rtf: nil)))
        XCTAssertNil(item.detectedURL)
    }

    func testInsertedURLMidSentenceHasDetectedURL() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.insert(item: .text("Check https://swift.org for details", rtf: nil)))
        XCTAssertNotNil(item.detectedURL)
        XCTAssertEqual(item.detectedURL?.host, "swift.org")
    }

    func testFetchedURLItemPreservesDetectedURL() throws {
        let store = makeStore()
        try store.insert(item: .text("https://swift.org", rtf: nil))
        let fetched = try XCTUnwrap(store.fetchAll().first)
        XCTAssertNotNil(fetched.detectedURL)
        XCTAssertEqual(fetched.detectedURL?.host, "swift.org")
    }

    func testFetchedPlainTextItemHasNoDetectedURL() throws {
        let store = makeStore()
        try store.insert(item: .text("no URL here", rtf: nil))
        let fetched = try XCTUnwrap(store.fetchAll().first)
        XCTAssertNil(fetched.detectedURL)
    }

    // MARK: - Helpers

    private func makeStore() -> HistoryStore {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imagesDir = tempDir.appendingPathComponent("images")
        try! FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let db = try! Database(path: tempDir.appendingPathComponent("test.db").path)
        let defaults = UserDefaults(suiteName: "URLDetectionTests.\(UUID().uuidString)")!
        defaults.set(500, forKey: "historyLimit")
        return HistoryStore(db: db, imagesDir: imagesDir, settings: SettingsManager(defaults: defaults))
    }
}
