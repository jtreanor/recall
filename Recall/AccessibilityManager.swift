import AppKit
import ApplicationServices

final class AccessibilityManager {
    static func requestAccessibilityIfNeeded() {
        guard !isAccessibilityTrusted() else { return }
        showAccessibilityAlert()
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
            Recall needs Accessibility permission to paste clipboard items into other apps. \
            Please grant access in System Settings > Privacy & Security > Accessibility, \
            then relaunch Recall.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
