import AppKit

final class OverlayPanel: NSPanel {
    static let panelHeight: CGFloat = 210
    var onDismiss: (() -> Void)?
    var onPaste: (() -> Void)?
    var onDelete: (() -> Void)?
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
        setFrame(visibleFrame(), display: false)
    }

    // Returns the on-screen resting frame.
    func visibleFrame() -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        return CGRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.minY,
            width: screen.frame.width,
            height: OverlayPanel.panelHeight
        )
    }

    // Returns the off-screen starting frame (below the screen edge).
    func offscreenFrame() -> CGRect {
        let vf = visibleFrame()
        return vf.offsetBy(dx: 0, dy: -OverlayPanel.panelHeight)
    }

    func show() {
        let target = visibleFrame()
        let start = offscreenFrame()

        setFrame(start, display: false)
        makeKeyAndOrderFront(nil)

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Escape
                if let state = self.overlayState {
                    if state.isSearchExpanded && !state.searchQuery.isEmpty {
                        state.searchQuery = ""
                    } else if state.isSearchExpanded {
                        state.isSearchExpanded = false  // collapse, clears query via didSet
                    } else {
                        self.hide()
                    }
                } else {
                    self.hide()
                }
                return nil
            case 124: // Right arrow
                self.overlayState?.moveSelection(by: 1)
                return nil
            case 123: // Left arrow
                self.overlayState?.moveSelection(by: -1)
                return nil
            case 36, 76: // Return, Enter (numpad)
                self.onPaste?()
                return nil
            case 51: // Backspace/Delete
                if let state = self.overlayState, state.isSearchExpanded && !state.searchQuery.isEmpty {
                    return event  // let TextField handle backspace within the query
                }
                self.onDelete?()
                return nil
            default:
                return event
            }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(target, display: true)
        }
    }

    func hide() {
        removeEventMonitors()
        onDismiss?()

        let end = offscreenFrame()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(end, display: true)
        } completionHandler: {
            self.orderOut(nil)
        }
    }

    private func removeEventMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
