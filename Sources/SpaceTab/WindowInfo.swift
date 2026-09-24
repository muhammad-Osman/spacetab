import AppKit

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    /// Nil when the app was too busy to answer Accessibility and had not been
    /// seen before. Switching to the window then brings its app to the front.
    let element: AXUIElement?

    /// Text to show in the switcher. Falls back to the app name for untitled windows.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
