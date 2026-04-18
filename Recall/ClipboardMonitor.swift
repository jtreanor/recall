import AppKit
import Combine

enum ClipboardItem {
    case text(String)
    case image(png: Data, thumbnail: NSImage)
}

final class ClipboardMonitor {
    let itemPublisher = PassthroughSubject<ClipboardItem, Never>()

    private let queue = DispatchQueue(label: "com.recall.clipboard", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.75, repeating: 0.75)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if let text = pb.string(forType: .string), !text.isEmpty {
            itemPublisher.send(.text(text))
            return
        }

        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            guard let data = pb.data(forType: type),
                  let image = NSImage(data: data) else { continue }
            guard let png = makePNG(from: image),
                  let thumb = makeThumbnail(from: image) else { return }
            itemPublisher.send(.image(png: png, thumbnail: thumb))
            return
        }
    }

    func makePNG(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    func makeThumbnail(from image: NSImage) -> NSImage? {
        let srcSize = image.size
        guard srcSize.width > 0, srcSize.height > 0 else { return nil }

        let scale = min(200.0 / srcSize.width, 150.0 / srcSize.height, 1.0)
        let w = Int((srcSize.width * scale).rounded())
        let h = Int((srcSize.height * scale).rounded())

        guard let cgSrc = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(
                  data: nil,
                  width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let thumbCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: thumbCG, size: CGSize(width: w, height: h))
    }
}
