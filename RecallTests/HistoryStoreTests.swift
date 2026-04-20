import XCTest
import AppKit
@testable import Recall

final class HistoryStoreTests: XCTestCase {
    var store: HistoryStore!
    var tempDir: URL!

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

    // MARK: - insert / fetchAll

    func testInsertTextAndFetch() throws {
        let item = try XCTUnwrap(store.insert(item: .text("hello")))
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "hello")
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].text, "hello")
    }

    func testDuplicateTextMovesToTop() throws {
        try store.insert(item: .text("hello"))
        try store.insert(item: .text("world"))
        let dup = try XCTUnwrap(store.insert(item: .text("hello")))
        XCTAssertEqual(dup.text, "hello")
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].text, "hello")
    }

    func testFetchAllNewestFirst() throws {
        try store.insert(item: .text("first"))
        try store.insert(item: .text("second"))
        let all = try store.fetchAll()
        XCTAssertEqual(all[0].text, "second")
        XCTAssertEqual(all[1].text, "first")
    }

    func testEmptyStoreReturnsEmptyArray() throws {
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    // MARK: - delete

    func testDeleteRemovesItem() throws {
        let item = try XCTUnwrap(store.insert(item: .text("delete me")))
        try store.delete(id: item.id)
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testDeleteUnknownIdIsNoop() throws {
        try store.insert(item: .text("keep"))
        try store.delete(id: 9999)
        XCTAssertEqual(try store.fetchAll().count, 1)
    }

    // MARK: - pruneToLimit

    func testPruneToLimitReducesCount() throws {
        for i in 0..<10 {
            try store.insert(item: .text("item \(i)"))
        }
        try store.pruneToLimit(5)
        XCTAssertEqual(try store.fetchAll().count, 5)
    }

    func testPruneKeepsNewest() throws {
        for i in 0..<5 {
            try store.insert(item: .text("item \(i)"))
        }
        try store.pruneToLimit(3)
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].text, "item 4")
    }

    func testPruneBelowExistingCountIsNoop() throws {
        try store.insert(item: .text("a"))
        try store.pruneToLimit(500)
        XCTAssertEqual(try store.fetchAll().count, 1)
    }

    // MARK: - images

    func testInsertImageWritesFile() throws {
        let png = makePNG()
        let item = try XCTUnwrap(store.insert(item: .image(png: png, thumbnail: NSImage())))
        XCTAssertEqual(item.kind, .image)
        let path = try XCTUnwrap(item.imagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testDeleteImageRemovesFile() throws {
        let png = makePNG()
        let item = try XCTUnwrap(store.insert(item: .image(png: png, thumbnail: NSImage())))
        let path = try XCTUnwrap(item.imagePath)
        try store.delete(id: item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testDuplicateImageMovesToTop() throws {
        let png = makePNG()
        let png2 = makePNG(seed: 99)
        try store.insert(item: .image(png: png, thumbnail: NSImage()))
        try store.insert(item: .image(png: png2, thumbnail: NSImage()))
        let dup = try XCTUnwrap(store.insert(item: .image(png: png, thumbnail: NSImage())))
        XCTAssertEqual(dup.kind, .image)
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].id, dup.id)
    }

    func testPruneDeletesImageFiles() throws {
        for _ in 0..<3 {
            let png = makePNG(seed: UInt8.random(in: 0...255))
            try store.insert(item: .image(png: png, thumbnail: NSImage()))
        }
        let pathsBefore = try store.fetchAll().compactMap(\.imagePath)
        XCTAssertEqual(pathsBefore.count, 3)

        try store.pruneToLimit(1)
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        let keptPath = try XCTUnwrap(all[0].imagePath)
        for path in pathsBefore where path != keptPath {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        }
    }

    // MARK: - count

    func testCountMatchesFetchAll() throws {
        try store.insert(item: .text("a"))
        try store.insert(item: .text("b"))
        XCTAssertEqual(try store.count(), try store.fetchAll().count)
    }

    // MARK: - Helpers

    private func makePNG(seed: UInt8 = 42) -> Data {
        let ctx = CGContext(
            data: nil, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let c = CGFloat(seed) / 255.0
        ctx.setFillColor(CGColor(red: c, green: 1 - c, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }
}
