import AppKit
import Combine

enum ClipboardItem {
    case text(String)
    case image(png: Data, thumbnail: NSImage)
}

struct CapturedItem {
    let item: ClipboardItem
    let sourceBundleId: String?
}

final class ClipboardMonitor {
    let itemPublisher = PassthroughSubject<CapturedItem, Never>()

    private let queue = DispatchQueue(label: "com.recall.clipboard", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var sleepWakeObservers: [NSObjectProtocol] = []
    private(set) var isSuspended = false
    var isRunning: Bool { timer != nil }

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        registerSleepWakeObservers()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        sleepWakeObservers.forEach { nc.removeObserver($0) }
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
        isSuspended = false
    }

    func stop() {
        if isSuspended {
            timer?.resume()
            isSuspended = false
        }
        timer?.cancel()
        timer = nil
    }

    func suspend() {
        guard !isSuspended, timer != nil else { return }
        timer?.suspend()
        isSuspended = true
    }

    func resume() {
        guard isSuspended, timer != nil else { return }
        timer?.resume()
        isSuspended = false
    }

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let suspendOn: [NSNotification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification
        ]
        let resumeOn: [NSNotification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification
        ]
        for name in suspendOn {
            sleepWakeObservers.append(
                nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.suspend() }
            )
        }
        for name in resumeOn {
            sleepWakeObservers.append(
                nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.resume() }
            )
        }
    }

    func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let text = pb.string(forType: .string), !text.isEmpty {
            itemPublisher.send(CapturedItem(item: .text(text), sourceBundleId: bundleId))
            return
        }

        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            guard let data = pb.data(forType: type),
                  let image = NSImage(data: data) else { continue }
            guard let png = makePNG(from: image),
                  let thumb = makeThumbnail(from: image) else { return }
            itemPublisher.send(CapturedItem(item: .image(png: png, thumbnail: thumb), sourceBundleId: bundleId))
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
