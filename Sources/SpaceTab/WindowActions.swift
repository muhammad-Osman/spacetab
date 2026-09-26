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

    /// Performs the action and returns whether the app took it. For minimize
    /// and hide, `restoring` means the opposite: bring the window back or
    /// show the app again. Accessibility calls wait for the app, so call it
    /// off the main thread.
    func perform(on window: WindowInfo, restoring: Bool) -> Bool {
        let element = window.element ?? AX.windows(of: window.pid).windows?.first { AX.windowID(of: $0) == window.id }
        switch self {
        case .close:
            // Pressing the close button lets the app ask to save changes.
            guard let element, let button = AX.element(kAXCloseButtonAttribute, of: element) else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        case .minimize:
            guard let element else { return false }
            return AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, (!restoring) as CFBoolean) == .success
        case .fullScreen:
            guard let element else { return false }
            let isFullScreen = (AX.value("AXFullScreen", of: element) as? Bool) ?? false
            return AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, (!isFullScreen) as CFBoolean) == .success
        case .quitApp:
            return DispatchQueue.main.sync {
                NSRunningApplication(processIdentifier: window.pid)?.terminate() ?? false
            }
        case .hideApp:
            return DispatchQueue.main.sync {
                guard let app = NSRunningApplication(processIdentifier: window.pid) else { return false }
                return restoring ? app.unhide() : app.hide()
            }
        }
    }
}
