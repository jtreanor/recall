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
    private var settingsWindowController: SettingsWindowController?
    private let toastController = ToastWindowController()
    private var accessibilityWarningItem: NSMenuItem?
    private var sensitiveItemSweepTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHistoryStore()
        setupOverlayPanel()
        startClipboardMonitor()
        startSensitiveItemSweep()
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
        let rootView = OverlayRootView(state: overlayState, onPaste: { [weak self] in self?.pasteSelectedItem() })
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        (panel.contentView as? NSVisualEffectView)?.addSubview(hostingView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        panel.overlayState = overlayState
        panel.onDismiss = { [weak self] in
            self?.isOverlayVisible = false
            self?.overlayState.isSearchExpanded = false  // clears searchQuery via didSet
        }
        panel.onPaste = { [weak self] in self?.pasteSelectedItem() }
        panel.onDelete = { [weak self] in self?.deleteSelectedItem() }
        overlayPanel = panel
    }

    private func startClipboardMonitor() {
        clipboardMonitor.itemPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] captured in self?.handleCapturedItem(captured) }
            .store(in: &cancellables)
        clipboardMonitor.start()
    }

    private func handleCapturedItem(_ captured: CapturedItem) {
        guard let store = historyStore else { return }
        do {
            let inserted = try store.insert(item: captured.item, sourceBundleId: captured.sourceBundleId, isSensitive: captured.isSensitive)
            let n = try store.count()
            if let inserted {
                print("[Recall] Stored \(inserted.kind) \(inserted.id) sensitive=\(inserted.isSensitive); history count: \(n)")
            }
            overlayState.items = (try? store.fetchAll()) ?? []
        } catch {
            print("[Recall] Store error: \(error)")
        }
    }

    private func startSensitiveItemSweep() {
        let queue = DispatchQueue(label: "com.recall.sensitive-sweep", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 300, repeating: 300, leeway: .seconds(30))
        t.setEventHandler { [weak self] in
            guard let self, let store = self.historyStore else { return }
            do {
                try store.sweepExpiredSensitive()
                DispatchQueue.main.async {
                    self.overlayState.items = (try? store.fetchAll()) ?? self.overlayState.items
                }
            } catch {
                print("[Recall] Sweep error: \(error)")
            }
        }
        t.resume()
        sensitiveItemSweepTimer = t
    }

    func showOverlay() {
        previousApp = NSWorkspace.shared.frontmostApplication
        isOverlayVisible = true
        overlayState.selectedIndex = 0
        try? historyStore?.pruneExpired(SettingsManager.shared.itemMaxAgeSecs)
        overlayState.items = (try? historyStore?.fetchAll()) ?? overlayState.items
        overlayPanel?.show()
    }

    func hideOverlay() {
        isOverlayVisible = false
        overlayPanel?.hide()
    }

    func pasteSelectedItem() {
        let idx = overlayState.selectedIndex
        let displayed = overlayState.filteredItems
        guard idx < displayed.count else { return }
        let item = displayed[idx]
        writeToPasteboard(item)

        guard AccessibilityManager.isAccessibilityTrusted() else {
            hideOverlay()
            toastController.show(message: "Copied — paste manually with ⌘V")
            return
        }

        let app = previousApp
        // Activate before starting hide animation so the previous app has
        // the full animation duration (~220ms) to take focus before ⌘V fires.
        app?.activate(options: .activateIgnoringOtherApps)
        hideOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            AppDelegate.postCommandV()
        }
    }

    func deleteSelectedItem() {
        let idx = overlayState.selectedIndex
        let displayed = overlayState.filteredItems
        guard idx < displayed.count else { return }
        let item = displayed[idx]
        try? historyStore?.delete(id: item.id)
        overlayState.items.removeAll { $0.id == item.id }
        let newCount = overlayState.filteredItems.count
        overlayState.selectedIndex = newCount > 0 ? min(idx, newCount - 1) : 0
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
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            button.image = icon
        }

        let menu = NSMenu()
        menu.delegate = self

        let warningItem = NSMenuItem(
            title: "⚠ Accessibility required",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        warningItem.isHidden = true
        menu.addItem(warningItem)
        accessibilityWarningItem = warningItem

        menu.addItem(NSMenuItem(title: "Show Recall", action: #selector(showRecall), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Recall", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityManager.openAccessibilitySettings()
    }

    @objc private func showRecall() {
        showOverlay()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController()
            controller.configureContent(
                onHotkeyChanged: { [weak self] in self?.hotkeyManager?.reregister() },
                onClearHistory: { [weak self] in self?.clearHistory() }
            )
            settingsWindowController = controller
        }
        settingsWindowController?.show()
    }

    private func clearHistory() {
        do {
            try historyStore?.clearAll()
            overlayState.items = []
        } catch {
            print("[Recall] Failed to clear history: \(error)")
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        accessibilityWarningItem?.isHidden = AccessibilityManager.isAccessibilityTrusted()
    }
}

enum SelectionStyle: CaseIterable {
    case borderOnly
    case subtleZoom
    case elevatedGlow

    var label: String {
        switch self {
        case .borderOnly:  return "Style 1 · Border"
        case .subtleZoom:  return "Style 2 · Zoom"
        case .elevatedGlow: return "Style 3 · Glow"
        }
    }

    var next: SelectionStyle {
        let all = SelectionStyle.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

final class OverlayState: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var selectedIndex: Int = 0
    @Published var searchQuery: String = "" {
        didSet { selectedIndex = 0 }
    }
    @Published var isSearchExpanded: Bool = false {
        didSet { if !isSearchExpanded { searchQuery = "" } }
    }
    @Published var selectionStyle: SelectionStyle = .borderOnly

    var filteredItems: [HistoryItem] {
        guard !searchQuery.isEmpty else { return items }
        let q = searchQuery.lowercased()
        return items.filter { item in
            guard item.kind == .text, let text = item.text else { return false }
            return text.lowercased().contains(q)
        }
    }

    func moveSelection(by delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }
}

private struct OverlayRootView: View {
    @ObservedObject var state: OverlayState
    var onPaste: (() -> Void)?

    var body: some View {
        OverlayView(
            items: state.filteredItems,
            totalItemCount: state.items.count,
            selectedIndex: $state.selectedIndex,
            searchQuery: $state.searchQuery,
            isSearchExpanded: $state.isSearchExpanded,
            selectionStyle: state.selectionStyle,
            onPaste: onPaste
        )
    }
}
