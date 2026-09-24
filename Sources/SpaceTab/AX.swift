import ApplicationServices

/// Private but long-stable API that maps an Accessibility window to its
/// CoreGraphics window ID. Every macOS window switcher relies on it.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

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

    /// A window's subrole and title, read in one call. Nil when the app didn't answer in time.
    static func subroleAndTitle(of element: AXUIElement) -> (subrole: String?, title: String)? {
        var values: CFArray?
        let attributes = [kAXSubroleAttribute, kAXTitleAttribute] as CFArray
        let result = AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(), &values)
        if result == .cannotComplete {
            return nil
        }
        // Missing attributes come back as error values, which aren't strings.
        guard result == .success, let array = values as? [Any], array.count == 2 else { return (nil, "") }
        return (array[0] as? String, array[1] as? String ?? "")
    }

    /// The window that has keyboard focus in the app, if any.
    static func focusedWindowID(of pid: pid_t) -> CGWindowID? {
        element(kAXFocusedWindowAttribute, of: AXUIElementCreateApplication(pid)).flatMap(windowID)
    }
}
