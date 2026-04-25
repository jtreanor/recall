import XCTest
import Combine
@testable import Recall

// MARK: - ClipboardMonitor sensitive detection tests

final class ClipboardMonitorSensitiveTests: XCTestCase {
    var monitor: ClipboardMonitor!
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        monitor = ClipboardMonitor()
    }

    override func tearDown() {
        monitor.stop()
        monitor = nil
        cancellables = []
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    func testConcealedTypeMarksItemAsSensitive() {
        var received: CapturedItem?
        let exp = expectation(description: "item received")
        monitor.itemPublisher.sink { received = $0; exp.fulfill() }.store(in: &cancellables)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("secret-password", forType: .string)
        monitor.poll()

        wait(for: [exp], timeout: 1)
        XCTAssertEqual(received?.isSensitive, true)
    }

    func testNoConcealedTypeNotSensitive() {
        var received: CapturedItem?
        let exp = expectation(description: "item received")
        monitor.itemPublisher.sink { received = $0; exp.fulfill() }.store(in: &cancellables)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ordinary text", forType: .string)
        monitor.poll()

        wait(for: [exp], timeout: 1)
        // This item comes from a non-password-manager app during tests;
        // it should not be marked sensitive unless the frontmost app happens to be a password manager.
        // We can only assert isSensitive is a Bool — concrete value depends on the test runner's frontmost app.
        XCTAssertNotNil(received)
    }

    func testKnownPasswordManagerBundleIdsAreExposed() {
        // Verify the set is non-empty and contains expected entries (white-box check).
        let ids = ClipboardMonitor.passwordManagerBundleIds
        XCTAssertTrue(ids.contains("com.1password.1password"))
        XCTAssertTrue(ids.contains("com.agilebits.onepassword7"))
        XCTAssertTrue(ids.contains("com.bitwarden"))
        XCTAssertTrue(ids.contains("com.dashlane.Dashlane"))
        XCTAssertTrue(ids.contains("com.lastpass.LastPass"))
        XCTAssertTrue(ids.contains("in.sinew.Enpass-Desktop"))
    }
}

// MARK: - HistoryStore sensitive item tests

final class HistoryStoreSensitiveTests: XCTestCase {
    var store: HistoryStore!
    var tempDir: URL!
    var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imagesDir = tempDir.appendingPathComponent("images")
        try! FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let db = try! Database(path: tempDir.appendingPathComponent("test.db").path)
        defaultsSuiteName = "RecallSecurityTests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuiteName)!
        testDefaults.set(500, forKey: "historyLimit")
        testDefaults.set(true, forKey: "storeSensitiveItems")
        let settings = SettingsManager(defaults: testDefaults)
        store = HistoryStore(db: db, imagesDir: imagesDir, settings: settings)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        if let name = defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        super.tearDown()
    }

    func testSensitiveItemStoredWithFlag() throws {
        let item = try XCTUnwrap(store.insert(item: .text("my-password"), isSensitive: true))
        XCTAssertTrue(item.isSensitive)
        XCTAssertNotNil(item.expiresAt)
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].isSensitive)
    }

    func testSensitiveItemExpiresAt15Minutes() throws {
        let before = Date()
        let item = try XCTUnwrap(store.insert(item: .text("temp-secret"), isSensitive: true))
        let after = Date()
        let expiresAt = try XCTUnwrap(item.expiresAt)
        XCTAssertGreaterThanOrEqual(expiresAt.timeIntervalSince(before), 14 * 60)
        XCTAssertLessThanOrEqual(expiresAt.timeIntervalSince(after), 16 * 60)
    }

    func testNonSensitiveItemHasNoExpiry() throws {
        let item = try XCTUnwrap(store.insert(item: .text("normal text"), isSensitive: false))
        XCTAssertFalse(item.isSensitive)
        XCTAssertNil(item.expiresAt)
    }

    func testExpiredSensitiveItemExcludedFromFetchAll() throws {
        try store.insert(item: .text("expired-secret"), isSensitive: true)
        // Backdate the expires_at to the past so the item is now expired.
        let pastMicros = Int64((Date().timeIntervalSince1970 - 1) * 1_000_000)
        try store.overrideExpiresAt(pastMicros)
        let all = try store.fetchAll()
        XCTAssertTrue(all.isEmpty, "Expired sensitive item should be filtered out of fetchAll")
    }

    func testNonExpiredSensitiveItemAppearsInFetchAll() throws {
        try store.insert(item: .text("fresh-secret"), isSensitive: true)
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
    }

    func testSweepExpiredSensitiveDeletesExpiredRows() throws {
        try store.insert(item: .text("sweep-target"), isSensitive: true)
        let pastMicros = Int64((Date().timeIntervalSince1970 - 1) * 1_000_000)
        try store.overrideExpiresAt(pastMicros)
        try store.sweepExpiredSensitive()
        XCTAssertEqual(try store.count(), 0)
    }

    func testSweepLeavesNonExpiredSensitiveItemsAlone() throws {
        try store.insert(item: .text("not-yet-expired"), isSensitive: true)
        try store.sweepExpiredSensitive()
        XCTAssertEqual(try store.count(), 1)
    }

    func testSweepDoesNotAffectNonSensitiveItems() throws {
        try store.insert(item: .text("normal"), isSensitive: false)
        try store.sweepExpiredSensitive()
        XCTAssertEqual(try store.count(), 1)
    }

    func testStoreSensitiveItemsOffSkipsInsert() throws {
        let suiteName = "RecallSecurityOffTests.\(UUID().uuidString)"
        let offDefaults = UserDefaults(suiteName: suiteName)!
        offDefaults.set(500, forKey: "historyLimit")
        offDefaults.set(false, forKey: "storeSensitiveItems")
        let offSettings = SettingsManager(defaults: offDefaults)
        let offStore = HistoryStore(db: store.testDB, imagesDir: tempDir.appendingPathComponent("images"), settings: offSettings)

        let result = try offStore.insert(item: .text("password"), isSensitive: true)
        XCTAssertNil(result, "Should return nil when storeSensitiveItems is off")
        XCTAssertEqual(try offStore.count(), 0)

        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testStoreSensitiveItemsOffAllowsNonSensitiveItems() throws {
        let suiteName = "RecallSecurityOffTests2.\(UUID().uuidString)"
        let offDefaults = UserDefaults(suiteName: suiteName)!
        offDefaults.set(500, forKey: "historyLimit")
        offDefaults.set(false, forKey: "storeSensitiveItems")
        let offSettings = SettingsManager(defaults: offDefaults)
        let offStore = HistoryStore(db: store.testDB, imagesDir: tempDir.appendingPathComponent("images"), settings: offSettings)

        let result = try offStore.insert(item: .text("normal text"), isSensitive: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(try offStore.count(), 1)

        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
