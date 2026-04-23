import AppKit
import Carbon
import SwiftUI

// MARK: - SettingsManager

struct SettingsManager {
    static let shared = SettingsManager()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hotkeyKeyCode: UInt32 {
        get {
            defaults.object(forKey: "hotkeyKeyCode") != nil
                ? UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
                : 9 // V
        }
        nonmutating set { defaults.set(Int(newValue), forKey: "hotkeyKeyCode") }
    }

    var hotkeyModifiers: UInt32 {
        get {
            defaults.object(forKey: "hotkeyModifiers") != nil
                ? UInt32(defaults.integer(forKey: "hotkeyModifiers"))
                : UInt32(cmdKey | shiftKey)
        }
        nonmutating set { defaults.set(Int(newValue), forKey: "hotkeyModifiers") }
    }

    var historyLimit: Int {
        get {
            let v = defaults.integer(forKey: "historyLimit")
            return v > 0 ? v : 500
        }
        nonmutating set { defaults.set(newValue, forKey: "historyLimit") }
    }

    func setHotkey(keyCode: UInt32, modifiers: UInt32) {
        self.hotkeyKeyCode = keyCode
        self.hotkeyModifiers = modifiers
    }
}

// MARK: - SettingsWindowController

final class SettingsWindowController: NSWindowController {
    var onHotkeyChanged: (() -> Void)?
    var onClearHistory: (() -> Void)?

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Recall Settings"
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
    }

    func configureContent(onHotkeyChanged: @escaping () -> Void, onClearHistory: @escaping () -> Void) {
        self.onHotkeyChanged = onHotkeyChanged
        self.onClearHistory = onClearHistory
        let view = SettingsView(onHotkeyChanged: onHotkeyChanged, onClearHistory: onClearHistory)
        window?.contentView = NSHostingView(rootView: view)
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    let onHotkeyChanged: () -> Void
    let onClearHistory: () -> Void

    @State private var keyCode: UInt32 = SettingsManager.shared.hotkeyKeyCode
    @State private var modifiers: UInt32 = SettingsManager.shared.hotkeyModifiers
    @State private var historyLimit: Int = SettingsManager.shared.historyLimit
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hotkey row
            HStack {
                Text("Global Shortcut")
                    .frame(width: 130, alignment: .leading)
                HotkeyRecorderField(keyCode: $keyCode, modifiers: $modifiers)
                    .onChange(of: keyCode) { _ in saveHotkey() }
                    .onChange(of: modifiers) { _ in saveHotkey() }
            }

            // History limit row
            HStack {
                Text("History Limit")
                    .frame(width: 130, alignment: .leading)
                Picker("", selection: $historyLimit) {
                    Text("50").tag(50)
                    Text("200").tag(200)
                    Text("500").tag(500)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: historyLimit) { newValue in
                    SettingsManager.shared.historyLimit = newValue
                }
            }

            Divider()

            // Clear history
            HStack {
                Spacer()
                Button("Clear All History…") {
                    showClearConfirm = true
                }
                .foregroundColor(.red)
                .alert("Clear All History?", isPresented: $showClearConfirm) {
                    Button("Clear", role: .destructive) { onClearHistory() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all clipboard history.")
                }
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func saveHotkey() {
        SettingsManager.shared.setHotkey(keyCode: keyCode, modifiers: modifiers)
        onHotkeyChanged()
    }
}

// MARK: - HotkeyRecorderField

struct HotkeyRecorderField: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button(label) {
            if isRecording { stopRecording() } else { startRecording() }
        }
        .buttonStyle(.bordered)
        .foregroundColor(isRecording ? .accentColor : .primary)
        .onDisappear { stopRecording() }
    }

    private var label: String {
        isRecording ? "Press shortcut…" : hotkeyString(keyCode: keyCode, modifiers: modifiers)
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if event.keyCode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !flags.isEmpty else { return event }
            keyCode = UInt32(event.keyCode)
            modifiers = carbonModifiers(from: flags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Hotkey display helpers

func hotkeyString(keyCode: UInt32, modifiers: UInt32) -> String {
    modifierString(from: modifiers) + keyName(for: keyCode)
}

func modifierString(from carbonMods: UInt32) -> String {
    var s = ""
    if carbonMods & UInt32(controlKey) != 0 { s += "⌃" }
    if carbonMods & UInt32(optionKey) != 0 { s += "⌥" }
    if carbonMods & UInt32(shiftKey) != 0 { s += "⇧" }
    if carbonMods & UInt32(cmdKey) != 0 { s += "⌘" }
    return s
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var c: UInt32 = 0
    if flags.contains(.command) { c |= UInt32(cmdKey) }
    if flags.contains(.shift)   { c |= UInt32(shiftKey) }
    if flags.contains(.option)  { c |= UInt32(optionKey) }
    if flags.contains(.control) { c |= UInt32(controlKey) }
    return c
}

func keyName(for code: UInt32) -> String {
    let table: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9",
        26: "7", 28: "8", 29: "0",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        49: "Space", 36: "Return", 51: "Delete", 48: "Tab",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        47: ".", 43: ",", 44: "/", 30: "]", 33: "[", 42: "\\",
        27: "-", 24: "=", 50: "`",
    ]
    return table[code] ?? "(\(code))"
}
