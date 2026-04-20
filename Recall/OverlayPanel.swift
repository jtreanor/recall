import AppKit

final class OverlayPanel: NSPanel {
    static let panelHeight: CGFloat = 180
    var onDismiss: (() -> Void)?
    var onPaste: (() -> Void)?
    weak var overlayState: OverlayState?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

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
        hasShadow = false
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        visual.layer?.masksToBounds = true
        contentView = visual
    }

    override var canBecomeKey: Bool { true }

    func positionAtScreenBottom() {
        guard let screen = NSScreen.main else { return }
        let frame = CGRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.minY,
            width: screen.frame.width,
            height: OverlayPanel.panelHeight
        )
        setFrame(frame, display: false)
    }

    func show() {
        positionAtScreenBottom()
        makeKeyAndOrderFront(nil)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Escape
                self.hide()
                return nil
            case 125: // Down arrow
                self.overlayState?.moveSelection(by: 1)
                return nil
            case 126: // Up arrow
                self.overlayState?.moveSelection(by: -1)
                return nil
            case 36, 76: // Return, Enter (numpad)
                self.onPaste?()
                return nil
            default:
                return event
            }
        }
    }

    func hide() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        onDismiss?()
        orderOut(nil)
    }
}
