import AppKit

final class OverlayPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private var localEventMonitor: Any?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isMovableByWindowBackground = false
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true
        contentView = visual
    }

    override var canBecomeKey: Bool { true }

    func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let sw = screen.visibleFrame.width
        let sh = screen.visibleFrame.height
        let pw: CGFloat = 480
        let ph: CGFloat = 400
        let ox = screen.visibleFrame.minX + (sw - pw) / 2
        let oy = screen.visibleFrame.minY + (sh - ph) / 2
        setFrame(CGRect(x: ox, y: oy, width: pw, height: ph), display: false)
    }

    func show() {
        centerOnMainScreen()
        makeKeyAndOrderFront(nil)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil
            }
            return event
        }
    }

    func hide() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        onDismiss?()
        orderOut(nil)
    }
}
