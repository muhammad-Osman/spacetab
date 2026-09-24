import AppKit
import ApplicationServices

enum WindowActivator {
    /// Brings the window's app to the front and raises the window above the
    /// app's other windows.
    ///
    /// Uses Accessibility rather than only `NSRunningApplication.activate()`,
    /// because since macOS 14 a background app can't reliably activate another app.
    static func activate(_ window: WindowInfo) {
        let app = AXUIElementCreateApplication(window.pid)
        _ = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }
}
