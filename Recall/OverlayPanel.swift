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

    // Approach O: the window never moves. The slide is a Core Animation
    // transform on this layer-backed view, which holds the backdrop and the
    // SwiftUI content. Render-server transform animations are immune to the
    // key/activation transitions that cancel window-frame (`animator().setFrame`)
    // slides — the exact race the paste flow triggers (activate previous app +
    // hide back-to-back). AppDelegate adds the hosting view as a subview of this.
    let slideView = NSVisualEffectView()

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
        // instant Recall deactivates. Kept false from approach N so the warm
        // panel survives deactivation; the slide itself no longer depends on it.
        hidesOnDeactivate = false
        backgroundColor = .clear
        hasShadow = false
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        slideView.material = .hudWindow
        slideView.state = .active
        slideView.wantsLayer = true
        slideView.layer?.cornerRadius = 12
        slideView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        slideView.layer?.masksToBounds = true

        // A plain layer-backed container is the contentView: we animate the
        // child slideView's layer transform, not the window's root content
        // layer (which AppKit re-lays-out and can reset). The container clips
        // the slideView to the window bounds as it travels below the edge.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = true
        slideView.autoresizingMask = [.width, .height]
        container.addSubview(slideView)
        contentView = container
        slideView.frame = container.bounds
    }

    override var canBecomeKey: Bool { true }

    // Approach M: order the panel in once at launch and keep it in the window
    // list permanently (alpha 0 while hidden), so the Window Server never
    // composites it from cold in show() — the cause of the first-composite
    // settle. The content transform is reset to identity (resting) here so the
    // next show() starts from a known state.
    func warmUp() {
        alphaValue = 0
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setContentTransform(CATransform3DIdentity)
        setFrame(visibleFrame(), display: true)
        orderFrontRegardless()
    }

    func positionAtScreenBottom() {
        setFrame(visibleFrame(), display: false)
    }

    // Returns the on-screen resting frame. The window stays here permanently.
    func visibleFrame() -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        return CGRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.minY,
            width: screen.frame.width,
            height: OverlayPanel.panelHeight
        )
    }

    // Content offset (layer space) that parks the slideView one panel-height
    // below the window's bottom edge — fully clipped, i.e. off-screen.
    private var hiddenTranslationY: CGFloat { -OverlayPanel.panelHeight }

    private func setContentTransform(_ transform: CATransform3D) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slideView.layer?.transform = transform
        CATransaction.commit()
    }

    func show() {
        ignoresMouseEvents = false
        // Pin to the active space while shown: a panel that joins all spaces
        // rides along on a space switch and flashes on the new space before
        // the space-change notification can hide it. Pinned, it stays behind
        // on the old space and the switch never shows it. warmUp() restores
        // canJoinAllSpaces so the hidden panel can be summoned anywhere.
        collectionBehavior = [.fullScreenAuxiliary]
        setFrame(visibleFrame(), display: false)

        // Pre-position the content fully below the edge with implicit actions
        // disabled, then flush so the render server has committed the
        // off-screen transform BEFORE alpha goes to 1 — otherwise a single
        // at-rest (on-screen) frame leaks before the slide starts.
        setContentTransform(CATransform3DMakeTranslation(0, hiddenTranslationY, 0))
        CATransaction.flush()

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

        // Settle the model at the resting transform, then drive the
        // presentation up from the off-screen offset. The explicit
        // CABasicAnimation (not the window animator) is what makes the slide
        // immune to activation races.
        setContentTransform(CATransform3DIdentity)
        let anim = CABasicAnimation(keyPath: "transform.translation.y")
        anim.fromValue = hiddenTranslationY
        anim.toValue = 0
        anim.duration = 0.15
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        slideView.layer?.add(anim, forKey: "slide")
    }

    func hide(animated: Bool = true) {
        removeEventMonitors()
        onDismiss?()

        guard animated else {
            finishHide()
            return
        }

        // Settle the model at the off-screen offset, drive the presentation
        // down to meet it, and finish (order out + re-warm) on completion.
        setContentTransform(CATransform3DMakeTranslation(0, hiddenTranslationY, 0))
        let anim = CABasicAnimation(keyPath: "transform.translation.y")
        anim.fromValue = 0
        anim.toValue = hiddenTranslationY
        anim.duration = 0.15
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.finishHide()
        }
        slideView.layer?.add(anim, forKey: "slide")
        CATransaction.commit()
    }

    // Approach M: resign key via orderOut, then immediately re-warm the panel
    // (back in the window list, alpha 0, content transform reset) so the
    // Window Server's first-composite settle decays invisibly now instead of
    // on the next show().
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
