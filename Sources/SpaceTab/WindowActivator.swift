import AppKit
@preconcurrency import ApplicationServices

/// Brings a window to the front and gives it keyboard focus.
///
/// Uses Accessibility rather than only `NSRunningApplication.activate()`,
/// because since macOS 14 a background app can't reliably activate another
/// app. Accessibility calls wait for the target app, so everything runs on
/// a serial background queue.
final class WindowActivator: @unchecked Sendable {
    /// When to check that the window really has focus, counted from the previous check.
    private static let checkDelays: [TimeInterval] = [0.1, 0.15, 0.25]

    private let queue = DispatchQueue(label: "SpaceTab.activation", qos: .userInteractive)
    /// Bumped for each switch, so checks for an older switch stop. Only used on `queue`.
    private var latest = 0

    /// Switches to the window. `done` runs on the main thread once the window
    /// has focus, or once SpaceTab has done what it can.
    func activate(_ window: WindowInfo, done: @escaping @MainActor () -> Void) {
        queue.async {
            self.latest += 1
            let token = self.latest
            // A window listed while its app was busy has no element yet; the
            // app has often recovered by now.
            let element = window.element ?? Self.findElement(of: window)
            let appAnswered = Self.bringForward(window, element: element)
            if appAnswered, let element {
                self.check(window, element: element, token: token, attempt: 0, done: done)
            } else {
                DispatchQueue.main.async { done() }
            }
        }
    }

    private static func findElement(of window: WindowInfo) -> AXUIElement? {
        AX.windows(of: window.pid).windows?.first { AX.windowID(of: $0) == window.id }
    }

    /// Returns false when the app didn't answer. More messages would only
    /// pile up in a hung app and replay later.
    private static func bringForward(_ window: WindowInfo, element: AXUIElement?) -> Bool {
        if let element {
            focus(element)
        }
        let app = AXUIElementCreateApplication(window.pid)
        let result = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if result != .success {
            let pid = window.pid
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
        if let element {
            _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        return result != .cannotComplete
    }

    /// Activation finishes asynchronously and can make the app's previous
    /// window key again. Check a few times and focus the chosen window again if so.
    private func check(
        _ window: WindowInfo,
        element: AXUIElement,
        token: Int,
        attempt: Int,
        done: @escaping @MainActor () -> Void
    ) {
        queue.asyncAfter(deadline: .now() + Self.checkDelays[attempt]) {
            guard token == self.latest else { return }
            let hasFocus = AX.focusedWindowID(of: window.pid) == window.id
            if !hasFocus {
                Self.focus(element)
            }
            if attempt == 0 {
                DispatchQueue.main.async { done() }
            }
            if !hasFocus, attempt + 1 < Self.checkDelays.count {
                self.check(window, element: element, token: token, attempt: attempt + 1, done: done)
            }
        }
    }

    private static func focus(_ element: AXUIElement) {
        _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}
