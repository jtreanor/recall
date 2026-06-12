import AppKit

final class OverlayPanel: NSPanel {
    static let panelHeight: CGFloat = 260
    var onDismiss: (() -> Void)?
    var onHidden: (() -> Void)?
    var onPaste: (() -> Void)?
    var onDelete: (() -> Void)?
    weak var overlayState: OverlayState?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var spaceChangeObserver: Any?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isMovableByWindowBackground = false
        isFloatingPanel = true
        level = .floating
        // NSPanel defaults this to true, so AppKit orders the panel out the
        // instant Recall deactivates — paste-back activates the previous app
        // before hide(), which skipped the close slide whenever Recall was
        // active (e.g. after using Settings). It would also evict the warm
        // panel (approach M) on every deactivation, re-cold-starting the
        // backdrop.
        hidesOnDeactivate = false
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

    // The slide animates through deliberately-offscreen frames (one panel
    // height below the screen). When Recall is the active app, AppKit's
    // default constraining snaps those frames back to the screen edge, so
    // both slides ran as instant jumps whenever Recall was active (e.g.
    // right after using Settings). All our frames are computed internally —
    // never constrain them.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // Approach M: order the panel in once at launch and keep it in the window
    // list permanently (alpha 0 while hidden), so the Window Server never
    // composites it from cold in show() — the cause of the first-composite
    // settle. Parked at the resting frame because a fully offscreen window may
    // not be composited, which would re-cold-start the backdrop.
    func warmUp() {
        alphaValue = 0
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrame(visibleFrame(), display: true)
        orderFrontRegardless()
    }

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

        ignoresMouseEvents = false
        // Pin to the active space while shown: a panel that joins all spaces
        // rides along on a space switch and flashes on the new space before
        // the space-change notification can hide it. Pinned, it stays behind
        // on the old space and the switch never shows it. warmUp() restores
        // canJoinAllSpaces so the hidden panel can be summoned anywhere.
        collectionBehavior = [.fullScreenAuxiliary]
        setFrame(start, display: false)
        alphaValue = 1
        makeKeyAndOrderFront(nil)

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        // Switching spaces takes key status from the panel (it joins all
        // spaces but stays unfocused), leaving Escape dead — dismiss instead.
        // Unanimated: the slide-out would play on the new space, making the
        // panel pop in just to animate away.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide(animated: false)
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
                if let state = self.overlayState, state.isSearchExpanded {
                    return event  // let TextField handle backspace when search is open
                }
                self.onDelete?()
                return nil
            default:
                // Auto-engage search on printable input when field is collapsed
                if let state = self.overlayState,
                   !state.isSearchExpanded,
                   event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                   let chars = event.characters, !chars.isEmpty,
                   chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
                    state.searchQuery = chars
                    state.isSearchExpanded = true
                    return nil
                }
                return event
            }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(target, display: true)
        }
    }

    func hide(animated: Bool = true) {
        removeEventMonitors()
        onDismiss?()

        guard animated else {
            finishHide()
            return
        }

        let end = offscreenFrame()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(end, display: true)
        } completionHandler: {
            self.finishHide()
        }
    }

    // Approach M: resign key via orderOut as before, then immediately
    // re-warm the panel (back in the window list, alpha 0, resting
    // frame) so the Window Server's first-composite settle decays
    // invisibly now instead of on the next show().
    private func finishHide() {
        orderOut(nil)
        warmUp()
        onHidden?()
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
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
    }
}
