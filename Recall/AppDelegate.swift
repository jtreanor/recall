import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let clipboardMonitor = ClipboardMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var historyStore: HistoryStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHistoryStore()
        startClipboardMonitor()
    }

    private func setupHistoryStore() {
        do {
            historyStore = try HistoryStore()
        } catch {
            print("[Recall] Failed to open history store: \(error)")
        }
    }

    private func startClipboardMonitor() {
        clipboardMonitor.itemPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in self?.handleClipboardItem(item) }
            .store(in: &cancellables)
        clipboardMonitor.start()
    }

    private func handleClipboardItem(_ item: ClipboardItem) {
        switch item {
        case .text(let string):
            print("[Recall] Text: \(string.prefix(80))")
        case .image(_, let thumbnail):
            print("[Recall] Image: \(Int(thumbnail.size.width))×\(Int(thumbnail.size.height)) thumbnail")
        }
        guard let store = historyStore else { return }
        do {
            guard let inserted = try store.insert(item: item) else { return }
            let n = try store.count()
            print("[Recall] Stored \(inserted.kind) \(inserted.id); history count: \(n)")
        } catch {
            print("[Recall] Store error: \(error)")
        }
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
