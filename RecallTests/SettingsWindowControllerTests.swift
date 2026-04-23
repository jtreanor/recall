import XCTest
import Carbon
@testable import Recall

final class SettingsManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.recall.tests.settings"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultHotkeyKeyCode() {
        // V key = 9
        let manager = makeManager()
        XCTAssertEqual(manager.hotkeyKeyCode, 9)
    }

    func testDefaultHotkeyModifiers() {
        // ⌘⇧ = cmdKey | shiftKey
        let manager = makeManager()
        let expected = UInt32(cmdKey | shiftKey)
        XCTAssertEqual(manager.hotkeyModifiers, expected)
    }

    func testDefaultHistoryLimit() {
        let manager = makeManager()
        XCTAssertEqual(manager.historyLimit, 500)
    }

    func testSaveAndReadHotkeyKeyCode() {
        let manager = makeManager()
        manager.hotkeyKeyCode = 8 // C
        XCTAssertEqual(defaults.object(forKey: "hotkeyKeyCode") as? Int, 8)
        XCTAssertEqual(manager.hotkeyKeyCode, 8)
    }

    func testSaveAndReadHotkeyModifiers() {
        let manager = makeManager()
        let mods = UInt32(cmdKey | optionKey)
        manager.hotkeyModifiers = mods
        XCTAssertEqual(manager.hotkeyModifiers, mods)
    }

    func testSaveAndReadHistoryLimit() {
        let manager = makeManager()
        manager.historyLimit = 50
        XCTAssertEqual(manager.historyLimit, 50)
        manager.historyLimit = 200
        XCTAssertEqual(manager.historyLimit, 200)
    }

    func testSetHotkey() {
        let manager = makeManager()
        manager.setHotkey(keyCode: 12, modifiers: UInt32(cmdKey))
        XCTAssertEqual(manager.hotkeyKeyCode, 12)
        XCTAssertEqual(manager.hotkeyModifiers, UInt32(cmdKey))
    }

    // MARK: - Helpers

    private func makeManager() -> SettingsManager {
        SettingsManager(defaults: defaults)
    }
}

final class HistoryStoreClearAllTests: XCTestCase {
    private var store: HistoryStore!
    private var imagesDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        imagesDir = tmp.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let db = try Database(path: tmp.appendingPathComponent("test.db").path)
        store = HistoryStore(db: db, imagesDir: imagesDir)
    }

    func testClearAllRemovesItems() throws {
        let item = ClipboardItem.text("hello")
        try store.insert(item: item)
        XCTAssertEqual(try store.count(), 1)
        try store.clearAll()
        XCTAssertEqual(try store.count(), 0)
    }

    func testClearAllRemovesImageFiles() throws {
        let png = makePNG()
        let thumb = NSImage(size: CGSize(width: 2, height: 2))
        try store.insert(item: .image(png: png, thumbnail: thumb))
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: imagesDir.path)
        XCTAssertFalse(filesBefore.isEmpty)
        try store.clearAll()
        let filesAfter = try FileManager.default.contentsOfDirectory(atPath: imagesDir.path)
        XCTAssertTrue(filesAfter.isEmpty)
    }

    func testClearAllOnEmptyStoreIsNoop() throws {
        XCTAssertNoThrow(try store.clearAll())
        XCTAssertEqual(try store.count(), 0)
    }

    // MARK: - Helpers

    private func makePNG() -> Data {
        let size = CGSize(width: 2, height: 2)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
}

final class HotkeyDisplayTests: XCTestCase {
    func testModifierString() {
        let mods = UInt32(cmdKey | shiftKey)
        let s = modifierString(from: mods)
        XCTAssertTrue(s.contains("⌘"))
        XCTAssertTrue(s.contains("⇧"))
        XCTAssertFalse(s.contains("⌥"))
    }

    func testKeyName() {
        XCTAssertEqual(keyName(for: 9), "V")
        XCTAssertEqual(keyName(for: 8), "C")
        XCTAssertEqual(keyName(for: 0), "A")
    }

    func testHotkeyStringDefaultShortcut() {
        let s = hotkeyString(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(s, "⇧⌘V")
    }
}
