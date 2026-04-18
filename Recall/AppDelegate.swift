import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let clipboardMonitor = ClipboardMonitor()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        startClipboardMonitor()
    }

    private func startClipboardMonitor() {
        clipboardMonitor.itemPublisher
            .sink { item in
                switch item {
                case .text(let string):
                    print("[Recall] Text: \(string.prefix(80))")
                case .image(_, let thumbnail):
                    print("[Recall] Image: \(Int(thumbnail.size.width))×\(Int(thumbnail.size.height)) thumbnail")
                }
            }
            .store(in: &cancellables)
        clipboardMonitor.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Recall")
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Recall", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
