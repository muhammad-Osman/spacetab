import AppKit
import ApplicationServices

enum AccessibilityPermission {
    /// Whether SpaceTab may use the Accessibility API and install a keyboard
    /// event tap. With `prompt`, macOS shows its permission dialog when not granted.
    static func isGranted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
