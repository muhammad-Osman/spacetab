import AppKit

struct WindowInfo {
    enum State: Sendable {
        case normal
        case minimized
        /// The window's app is hidden (⌘H).
        case appHidden
    }

    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    /// Nil when the app was too busy to answer Accessibility and had not been
    /// seen before. Switching to the window then looks it up again.
    let element: AXUIElement?
    var state: State = .normal

    /// Text to show in the switcher. Falls back to the app name for untitled windows.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
