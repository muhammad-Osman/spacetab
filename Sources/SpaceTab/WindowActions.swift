import AppKit
@preconcurrency import ApplicationServices

/// What you can do to the selected window without leaving the switcher.
enum WindowAction: Sendable {
    case close
    case minimize
    case quitApp
    case fullScreen
    case hideApp

    /// The action for a key in the switcher: W, M, Q, F or H.
    init?(character: String) {
        switch character.lowercased() {
        case "w": self = .close
        case "m": self = .minimize
        case "q": self = .quitApp
        case "f": self = .fullScreen
        case "h": self = .hideApp
        default: return nil
        }
    }

    /// Performs the action. Accessibility calls wait for the app, so call it
    /// off the main thread.
    func perform(on window: WindowInfo) {
        let element = window.element ?? AX.windows(of: window.pid).windows?.first { AX.windowID(of: $0) == window.id }
        switch self {
        case .close:
            // Pressing the close button lets the app ask to save changes.
            if let element, let button = AX.element(kAXCloseButtonAttribute, of: element) {
                _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
        case .minimize:
            if let element {
                let isMinimized = (AX.value(kAXMinimizedAttribute, of: element) as? Bool) ?? false
                _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, (!isMinimized) as CFBoolean)
            }
        case .fullScreen:
            if let element {
                let attribute = "AXFullScreen" as CFString
                let isFullScreen = (AX.value("AXFullScreen", of: element) as? Bool) ?? false
                _ = AXUIElementSetAttributeValue(element, attribute, (!isFullScreen) as CFBoolean)
            }
        case .quitApp:
            let pid = window.pid
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: pid)?.terminate()
            }
        case .hideApp:
            let pid = window.pid
            DispatchQueue.main.async {
                guard let app = NSRunningApplication(processIdentifier: pid) else { return }
                _ = app.isHidden ? app.unhide() : app.hide()
            }
        }
    }
}
