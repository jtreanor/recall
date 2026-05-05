import AppKit
import QuartzCore

final class OverlayPanel: NSPanel {
    static let panelHeight: CGFloat = 260
    var onDismiss: (() -> Void)?
    var onHidden: (() -> Void)?
    var onPaste: (() -> Void)?
    var onDelete: (() -> Void)?
    weak var overlayState: OverlayState?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

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

    func show() {
        // Cancel any in-flight hide animation and snap layer back to identity.
        contentView?.layer?.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView?.layer?.transform = CATransform3DIdentity
        CATransaction.commit()

        setFrame(visibleFrame(), display: false)
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

        // Slide content up via layer transform. The window frame stays fixed at visibleFrame()
        // so x can never drift during animation.
        let slideIn = CABasicAnimation(keyPath: "transform")
        slideIn.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, -OverlayPanel.panelHeight, 0))
        slideIn.duration = 0.15
        slideIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // toValue defaults to the model value (CATransform3DIdentity).
        contentView?.layer?.add(slideIn, forKey: "slide")
    }

    func hide() {
        removeEventMonitors()
        onDismiss?()

        let slideOut = CABasicAnimation(keyPath: "transform")
        slideOut.toValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, -OverlayPanel.panelHeight, 0))
        slideOut.duration = 0.15
        slideOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // fillMode keeps the final frame visible until orderOut removes the window.
        slideOut.fillMode = .forwards
        slideOut.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.contentView?.layer?.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.contentView?.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
            self.orderOut(nil)
            self.onHidden?()
        }
        contentView?.layer?.add(slideOut, forKey: "slide")
        CATransaction.commit()
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
