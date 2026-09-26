import ApplicationServices

/// Private but long-stable API that maps an Accessibility window to its
/// CoreGraphics window ID. Every macOS window switcher relies on it.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Private: makes an element from a token naming an app and an element ID.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

/// Small wrappers around the Accessibility API. Each call waits for the target
/// app (up to the global messaging timeout), so avoid calling them on the main thread.
enum AX {
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    static func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = value(attribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /// The app's windows. Nil in `windows` with `busy` set when the app didn't answer in time.
    static func windows(of pid: pid_t) -> (windows: [AXUIElement]?, busy: Bool) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value
        )
        guard result == .success else { return (nil, result == .cannotComplete) }
        return (value as? [AXUIElement], false)
    }

    struct WindowAttributes {
        var subrole: String?
        var title = ""
        var isMinimized = false
    }

    /// A window's subrole, title and minimized state, read in one call. Nil
    /// when the app didn't answer in time.
    static func windowAttributes(of element: AXUIElement) -> WindowAttributes? {
        var values: CFArray?
        let attributes = [kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute] as CFArray
        let result = AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(), &values)
        if result == .cannotComplete {
            return nil
        }
        // Missing attributes come back as error values, which aren't strings or booleans.
        guard result == .success, let array = values as? [Any], array.count == 3 else { return WindowAttributes() }
        return WindowAttributes(
            subrole: array[0] as? String,
            title: array[1] as? String ?? "",
            isMinimized: (array[2] as? Bool) ?? false
        )
    }

    /// After this many element IDs the search starts over.
    static let bruteForceLimit: UInt64 = 100_000

    /// Finds windows the app doesn't report, such as windows on other
    /// desktops, by trying element IDs from `cursor` on. Stops once every
    /// wanted window is found or `budget` seconds have passed, and returns
    /// where to continue next time. Each try asks the app, so keep the budget small.
    static func windowsByBruteForce(
        pid: pid_t,
        wanted: Set<CGWindowID>,
        from cursor: UInt64,
        budget: TimeInterval
    ) -> (found: [CGWindowID: AXUIElement], cursor: UInt64) {
        let deadline = Date().addingTimeInterval(budget)
        var remaining = wanted
        var found: [CGWindowID: AXUIElement] = [:]
        var elementID = cursor
        var tries: UInt64 = 0
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
        while !remaining.isEmpty, tries < bruteForceLimit, Date() < deadline {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            if let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
               let id = windowID(of: element), remaining.remove(id) != nil {
                found[id] = element
            }
            elementID = (elementID + 1) % bruteForceLimit
            tries += 1
        }
        return (found, elementID)
    }

    /// Whether the app is the one in front.
    static func isFrontmost(_ pid: pid_t) -> Bool {
        (value(kAXFrontmostAttribute, of: AXUIElementCreateApplication(pid)) as? Bool) ?? false
    }

    /// The window that has keyboard focus in the app, if any.
    static func focusedWindowID(of pid: pid_t) -> CGWindowID? {
        element(kAXFocusedWindowAttribute, of: AXUIElementCreateApplication(pid)).flatMap(windowID)
    }
}
