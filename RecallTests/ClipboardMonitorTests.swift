import XCTest
import Combine
@testable import Recall

final class ClipboardMonitorTests: XCTestCase {

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
        super.tearDown()
    }

    // MARK: - ClipboardItem model

    func testTextCaseStoresString() {
        let item = ClipboardItem.text("hello")
        guard case .text(let s) = item else { return XCTFail("expected .text") }
        XCTAssertEqual(s, "hello")
    }

    func testImageCaseStoresPayload() {
        let png = Data([0x89, 0x50])
        let thumb = NSImage(size: CGSize(width: 10, height: 10))
        let item = ClipboardItem.image(png: png, thumbnail: thumb)
        guard case .image(let p, let t) = item else { return XCTFail("expected .image") }
        XCTAssertEqual(p, png)
        XCTAssertEqual(t.size, thumb.size)
    }

    // MARK: - makePNG

    func testMakePNGReturnsPNGData() throws {
        let image = solidColorImage(size: CGSize(width: 10, height: 10))
        let data = try XCTUnwrap(monitor.makePNG(from: image))
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // MARK: - makeThumbnail

    func testThumbnailFitsWithinBounds() throws {
        let image = solidColorImage(size: CGSize(width: 800, height: 600))
        let thumb = try XCTUnwrap(monitor.makeThumbnail(from: image))
        XCTAssertLessThanOrEqual(thumb.size.width, 200)
        XCTAssertLessThanOrEqual(thumb.size.height, 150)
    }

    func testThumbnailPreservesAspectRatio() throws {
        let image = solidColorImage(size: CGSize(width: 400, height: 200))
        let thumb = try XCTUnwrap(monitor.makeThumbnail(from: image))
        XCTAssertEqual(thumb.size.width / thumb.size.height, 2.0, accuracy: 0.05)
    }

    func testThumbnailDoesNotUpscaleSmallImage() throws {
        let image = solidColorImage(size: CGSize(width: 50, height: 40))
        let thumb = try XCTUnwrap(monitor.makeThumbnail(from: image))
        XCTAssertEqual(thumb.size.width, 50, accuracy: 1)
        XCTAssertEqual(thumb.size.height, 40, accuracy: 1)
    }

    // MARK: - poll / publish

    func testPollEmitsTextOnPasteboardChange() {
        let exp = expectation(description: "text emitted")
        var received: ClipboardItem?
        monitor.itemPublisher.sink { received = $0; exp.fulfill() }
            .store(in: &cancellables)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("unit-test", forType: .string)
        monitor.poll()

        wait(for: [exp], timeout: 1)
        guard case .text(let s) = received else { return XCTFail("expected .text") }
        XCTAssertEqual(s, "unit-test")
    }

    func testPollDoesNotEmitTwiceForSameChange() {
        var count = 0
        monitor.itemPublisher.sink { _ in count += 1 }.store(in: &cancellables)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("once", forType: .string)
        monitor.poll()  // emits
        monitor.poll()  // same changeCount — silent
        XCTAssertEqual(count, 1)
    }

    // MARK: - helpers

    private func solidColorImage(size: CGSize) -> NSImage {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return NSImage(cgImage: ctx.makeImage()!, size: size)
    }
}
