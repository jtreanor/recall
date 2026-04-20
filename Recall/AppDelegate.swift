import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let clipboardMonitor = ClipboardMonitor()
    private var cancellables = Set<AnyCancellable>()
    var historyStore: HistoryStore?

    private var overlayPanel: OverlayPanel?
    let overlayState = OverlayState()
    private var hotkeyManager: HotkeyManager?
    var isOverlayVisible = false
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHistoryStore()
        setupOverlayPanel()
        startClipboardMonitor()
        setupHotkey()
        AccessibilityManager.requestAccessibilityIfNeeded()
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
        panel.overlayState = overlayState
        panel.onDismiss = { [weak self] in self?.isOverlayVisible = false }
        panel.onPaste = { [weak self] in self?.pasteSelectedItem() }
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
            let inserted = try store.insert(item: item)
            let n = try store.count()
            if let inserted {
                print("[Recall] Stored \(inserted.kind) \(inserted.id); history count: \(n)")
            }
            overlayState.items = (try? store.fetchAll()) ?? []
        } catch {
            print("[Recall] Store error: \(error)")
        }
    }

    func showOverlay() {
        previousApp = NSWorkspace.shared.frontmostApplication
        isOverlayVisible = true
        overlayState.selectedIndex = 0
        overlayState.items = (try? historyStore?.fetchAll()) ?? overlayState.items
        overlayPanel?.show()
    }

    func hideOverlay() {
        isOverlayVisible = false
        overlayPanel?.hide()
    }

    func pasteSelectedItem() {
        let idx = overlayState.selectedIndex
        guard idx < overlayState.items.count else { return }
        let item = overlayState.items[idx]
        writeToPasteboard(item)
        let app = previousApp
        hideOverlay()
        app?.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppDelegate.postCommandV()
        }
    }

    func writeToPasteboard(_ item: HistoryItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.kind == .text, let text = item.text {
            pb.setString(text, forType: .string)
        } else if item.kind == .image, let path = item.imagePath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            pb.setData(data, forType: .png)
        }
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            guard let self else { return }
            if self.isOverlayVisible {
                self.hideOverlay()
            } else {
                self.showOverlay()
            }
        }
        hotkeyManager?.register()
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

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
    }
}

private struct OverlayRootView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        OverlayView(items: state.items, selectedIndex: $state.selectedIndex)
    }
}
