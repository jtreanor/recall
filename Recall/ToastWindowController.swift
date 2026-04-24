import AppKit
import SwiftUI

final class ToastWindowController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(message: String, duration: TimeInterval = 2.5) {
        dismissWork?.cancel()
        panel?.close()
        panel = nil

        let toastPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toastPanel.isOpaque = false
        toastPanel.backgroundColor = .clear
        toastPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        toastPanel.hasShadow = false
        toastPanel.ignoresMouseEvents = true
        toastPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toastPanel.contentView = NSHostingView(rootView: ToastLabel(message: message))

        if let screen = NSScreen.main {
            let toastX = screen.frame.midX - 160
            let toastY = screen.visibleFrame.minY + OverlayPanel.panelHeight + 16
            toastPanel.setFrameOrigin(NSPoint(x: toastX, y: toastY))
        }

        toastPanel.alphaValue = 0
        toastPanel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toastPanel.animator().alphaValue = 1
        }
        panel = toastPanel

        let work = DispatchWorkItem { [weak self, weak toastPanel] in
            guard let toastPanel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                toastPanel.animator().alphaValue = 0
            } completionHandler: {
                toastPanel.close()
                self?.panel = nil
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

private struct ToastLabel: View {
    let message: String

    var body: some View {
        HStack {
            Spacer()
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.8)))
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}
