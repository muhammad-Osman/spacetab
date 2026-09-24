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
    /// A minimized window first has to come out of the Dock.
    private static let minimizedCheckDelays: [TimeInterval] = [0.1, 0.15, 0.25, 0.3]
    /// How long to wait for a first answer before treating the app as hung.
    private static let probeTimeout: Float = 0.1

    private let queue = DispatchQueue(label: "SpaceTab.activation", qos: .userInteractive)
    /// Bumped for each switch, so checks for an older switch stop. Only used on `queue`.
    private var latest = 0

    /// Switches to the window. `done` runs on the main thread once the window
    /// has focus or SpaceTab has done what it can. Its argument is false when
    /// the app didn't answer, so the window may not be in front.
    func activate(_ window: WindowInfo, done: @escaping @MainActor (Bool) -> Void) {
        queue.async {
            self.latest += 1
            let token = self.latest
            guard Self.isResponding(window.pid) else {
                // A hung app would queue every message and act on them later,
                // jumping in front while you work elsewhere. Only ask macOS.
                DispatchQueue.main.async {
                    NSRunningApplication(processIdentifier: window.pid)?.activate()
                    done(false)
                }
                return
            }
            // A window listed while its app was busy has no element yet; the
            // app has often recovered by now.
            let element = window.element ?? Self.findElement(of: window)
            Self.bringForward(window, element: element)
            guard let element else {
                DispatchQueue.main.async { done(false) }
                return
            }
            let delays = window.state == .minimized ? Self.minimizedCheckDelays : Self.checkDelays
            self.check(window, element: element, token: token, attempt: 0, delays: delays, done: done)
        }
    }

    private static func isResponding(_ pid: pid_t) -> Bool {
        let probe = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(probe, probeTimeout)
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(probe, kAXRoleAttribute as CFString, &role) != .cannotComplete
    }

    private static func findElement(of window: WindowInfo) -> AXUIElement? {
        AX.windows(of: window.pid).windows?.first { AX.windowID(of: $0) == window.id }
    }

    private static func bringForward(_ window: WindowInfo, element: AXUIElement?) {
        let app = AXUIElementCreateApplication(window.pid)
        if window.state == .appHidden {
            _ = AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, kCFBooleanFalse)
        }
        if let element {
            if window.state == .minimized {
                _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            focus(element)
        }
        if AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) != .success {
            let pid = window.pid
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
        if let element {
            _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    /// Activation finishes asynchronously and can make the app's previous
    /// window key again. Check until the chosen window has focus in the app in
    /// front, focusing it again when it doesn't. `done` runs when it does, or
    /// after the last check.
    private func check(
        _ window: WindowInfo,
        element: AXUIElement,
        token: Int,
        attempt: Int,
        delays: [TimeInterval],
        done: @escaping @MainActor (Bool) -> Void
    ) {
        queue.asyncAfter(deadline: .now() + delays[attempt]) {
            guard token == self.latest else { return }
            let ready = AX.focusedWindowID(of: window.pid) == window.id && AX.isFrontmost(window.pid)
            let isLast = attempt + 1 == delays.count
            if !ready {
                Self.focus(element)
            }
            if ready || isLast {
                DispatchQueue.main.async { done(true) }
            } else {
                self.check(window, element: element, token: token, attempt: attempt + 1, delays: delays, done: done)
            }
        }
    }

    private static func focus(_ element: AXUIElement) {
        _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}
