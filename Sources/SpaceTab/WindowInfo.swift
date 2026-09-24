import AppKit

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let element: AXUIElement

    /// Text to show in the switcher. Falls back to the app name for untitled windows.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
