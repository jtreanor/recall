import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let clipboardMonitor = ClipboardMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var historyStore: HistoryStore?

    private var overlayPanel: OverlayPanel?
    let overlayState = OverlayState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHistoryStore()
        setupOverlayPanel()
        startClipboardMonitor()
    }

    private func setupHistoryStore() {
        do {
            historyStore = try HistoryStore()
            overlayState.items = (try? historyStore?.fetchAll()) ?? []
        } catch {
            print("[Recall] Failed to open history store: \(error)")
        }
    }

    private func setupOverlayPanel() {
        let panel = OverlayPanel()
        let rootView = OverlayRootView(state: overlayState)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        (panel.contentView as? NSVisualEffectView)?.addSubview(hostingView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        overlayPanel = panel
    }

    private func startClipboardMonitor() {
        clipboardMonitor.itemPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in self?.handleClipboardItem(item) }
            .store(in: &cancellables)
        clipboardMonitor.start()
    }

    private func handleClipboardItem(_ item: ClipboardItem) {
        guard let store = historyStore else { return }
        do {
            guard let inserted = try store.insert(item: item) else { return }
            let n = try store.count()
            print("[Recall] Stored \(inserted.kind) \(inserted.id); history count: \(n)")
            overlayState.items = (try? store.fetchAll()) ?? []
        } catch {
            print("[Recall] Store error: \(error)")
        }
    }

    func showOverlay() {
        overlayState.selectedIndex = 0
        overlayPanel?.show()
    }

    func hideOverlay() {
        overlayPanel?.hide()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Recall")
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Recall", action: #selector(showRecall), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Recall", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showRecall() {
        showOverlay()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

final class OverlayState: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var selectedIndex: Int = 0
}

private struct OverlayRootView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        OverlayView(items: state.items, selectedIndex: $state.selectedIndex)
    }
}
