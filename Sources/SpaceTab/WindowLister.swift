import AppKit
import ApplicationServices

/// Private but long-stable API that maps an Accessibility window to its
/// CoreGraphics window ID. Every macOS window switcher relies on it.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowLister {
    /// Windows on the current desktop, front to back.
    ///
    /// On-screen windows are exactly the ones on the desktop you are looking at,
    /// and front-to-back order is most recently used order. Minimized and hidden
    /// windows are not included yet.
    ///
    /// CoreGraphics gives the list and order. Titles come from the Accessibility
    /// API, because CoreGraphics only reports titles with Screen Recording permission.
    static func windowsOnCurrentDesktop() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var axWindowsByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var windows: [WindowInfo] = []

        for entry in entries {
            guard
                (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                pid != ownPID,
                (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                let app = NSRunningApplication(processIdentifier: pid),
                app.activationPolicy == .regular
            else { continue }

            let axWindows = axWindowsByPID[pid] ?? accessibilityWindows(of: pid)
            axWindowsByPID[pid] = axWindows

            // Windows the app doesn't report to Accessibility are overlays,
            // tooltips and the like, not real windows.
            guard let element = axWindows[id] else { continue }

            windows.append(WindowInfo(
                id: id,
                pid: pid,
                appName: app.localizedName ?? "",
                title: stringAttribute(kAXTitleAttribute, of: element) ?? "",
                icon: app.icon,
                element: element
            ))
        }
        return windows
    }

    private static func accessibilityWindows(of pid: pid_t) -> [CGWindowID: AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let elements = value as? [AXUIElement]
        else { return [:] }

        var result: [CGWindowID: AXUIElement] = [:]
        for element in elements {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(element, &id) == .success {
                result[id] = element
            }
        }
        return result
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
