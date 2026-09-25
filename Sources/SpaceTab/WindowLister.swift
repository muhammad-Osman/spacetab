import AppKit
@preconcurrency import ApplicationServices

struct WindowList {
    /// Most recently used first.
    let windows: [WindowInfo]
    /// Whether the first window is the one you are switching away from.
    let firstIsCurrent: Bool
}

/// Lists the windows on the current desktop.
///
/// Makes Accessibility calls, which wait for other apps, so use it off the main
/// thread. Keeps a cache between calls: use one instance from one serial queue.
final class WindowLister: @unchecked Sendable {
    private enum Lookup {
        case answered([CGWindowID: AXUIElement])
        /// The app didn't answer in time.
        case busy
        /// The app doesn't report windows to Accessibility.
        case unavailable
    }

    private struct CachedWindow {
        let element: AXUIElement
        let title: String
    }

    /// Windows each app reported, used while the app is too busy to answer.
    private var lastKnown: [pid_t: [CGWindowID: CachedWindow]] = [:]
    /// Windows each app reported last time that the filter left out.
    private var lastRejected: [pid_t: Set<CGWindowID>] = [:]

    /// IDs of the normal windows on screen, front to back.
    static func onScreenWindowIDs() -> [CGWindowID] {
        onScreenEntries().compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
    }

    /// The app's front-most normal window on screen, found without asking the app.
    static func topWindowID(of pid: pid_t) -> CGWindowID? {
        for entry in onScreenEntries() {
            guard
                (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
            else { continue }
            return (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
        return nil
    }

    /// Windows on the current desktop (or on all desktops, when the options
    /// say so), most recently used first.
    ///
    /// On-screen windows are exactly the ones on the desktop you are looking at.
    /// Minimized windows, windows of hidden apps and windows on other desktops
    /// are off screen, so their desktop is looked up with private Spaces APIs.
    /// CoreGraphics gives the list. Titles come from the Accessibility API,
    /// because CoreGraphics only reports titles with Screen Recording permission.
    func windowsOnCurrentDesktop(
        ranks: [CGWindowID: Int],
        frontmostPID: pid_t?,
        pendingSwitch: PendingSwitch?,
        options: ListingOptions
    ) -> WindowList {
        var lookups: [pid_t: Lookup] = [:]
        var fresh: [pid_t: [CGWindowID: CachedWindow]] = [:]
        var rejected: [pid_t: Set<CGWindowID>] = [:]
        /// Windows an answering app was asked about, accepted or not.
        var examined: [pid_t: Set<CGWindowID>] = [:]
        var windows: [WindowInfo] = []

        let onScreen = Self.onScreenEntries()
        for entry in onScreen {
            guard let (id, pid, bounds, app) = Self.candidate(entry, options: options) else { continue }

            var lookup = lookups[pid] ?? accessibilityWindows(of: pid)
            lookups[pid] = lookup

            var element: AXUIElement?
            var title = ""
            var resolved = false
            if case let .answered(axWindows) = lookup {
                examined[pid, default: []].insert(id)
                guard let found = axWindows[id] else {
                    // Windows the app doesn't report to Accessibility are
                    // overlays, tooltips and the like, not real windows.
                    rejected[pid, default: []].insert(id)
                    continue
                }
                if let attributes = AX.windowAttributes(of: found) {
                    guard Self.isSwitchable(subrole: attributes.subrole, title: attributes.title, size: bounds.size) else {
                        rejected[pid, default: []].insert(id)
                        continue
                    }
                    element = found
                    title = attributes.title
                    resolved = true
                    fresh[pid, default: [:]][id] = CachedWindow(element: found, title: title)
                } else {
                    // The app stopped answering partway through. Don't wait on it again.
                    lookup = .busy
                    lookups[pid] = .busy
                }
            }

            if !resolved {
                guard case .busy = lookup, lastRejected[pid]?.contains(id) != true else { continue }
                if let cached = lastKnown[pid]?[id] {
                    // The app is busy. Use what it reported last time.
                    element = cached.element
                    title = cached.title
                } else {
                    // The app is busy and this window is new. Still list it, so
                    // the app doesn't vanish from the switcher.
                    guard Self.isLargeEnough(bounds.size) else { continue }
                }
            }

            windows.append(WindowInfo(
                id: id,
                pid: pid,
                appName: app.localizedName ?? "",
                title: title,
                icon: app.icon,
                element: element
            ))
        }

        if options.allDesktops || options.minimizedWindows != .hidden || options.hiddenAppWindows != .hidden {
            let onScreenIDs = Set(onScreen.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
            windows += offScreenWindows(excluding: onScreenIDs, options: options, lookups: &lookups)
        }

        updateCache(lookups: lookups, fresh: fresh, rejected: rejected, examined: examined)

        var focusedID: CGWindowID?
        if let frontmostPID, case .answered = lookups[frontmostPID] {
            focusedID = AX.focusedWindowID(of: frontmostPID)
        }
        // With one screen chosen, the window you are in may be on another
        // screen. Then the first listed window isn't the current one, even
        // if it belongs to the same app.
        var focusedElsewhere = false
        if options.onlyScreen != nil, let frontmostPID {
            let focusedEntry = onScreen.first { entry in
                let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value
                let isNormal = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                return focusedID.map { id == $0 } ?? (pid == frontmostPID && isNormal)
            }
            if let boundsDictionary = focusedEntry?[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) {
                focusedElsewhere = !options.includes(bounds)
            }
        }
        var atEnd = Set<WindowInfo.State>()
        if options.minimizedWindows == .atEnd { atEnd.insert(.minimized) }
        if options.hiddenAppWindows == .atEnd { atEnd.insert(.appHidden) }
        return Self.order(
            windows,
            ranks: ranks,
            focusedID: focusedID,
            frontmostPID: frontmostPID,
            pendingSwitch: pendingSwitch,
            focusedElsewhere: focusedElsewhere,
            atEnd: atEnd,
            groupByApp: options.groupByApp
        )
    }

    /// Minimized windows and windows of hidden apps on the current desktop,
    /// and windows on other desktops when asked for.
    private func offScreenWindows(
        excluding onScreenIDs: Set<CGWindowID>,
        options: ListingOptions,
        lookups: inout [pid_t: Lookup]
    ) -> [WindowInfo] {
        guard let currentSpaces = Spaces.currentSpaceIDs() else { return [] }
        let entries = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var windows: [WindowInfo] = []

        for entry in entries {
            guard
                let (id, pid, bounds, app) = Self.candidate(entry, options: options),
                !onScreenIDs.contains(id),
                Self.isLargeEnough(bounds.size)
            else { continue }
            let spaces = Spaces.spaceIDs(of: id)
            let onCurrentDesktop = !spaces.isDisjoint(with: currentSpaces)
            // A window on no desktop was closed but kept by its app.
            guard onCurrentDesktop || (options.allDesktops && !spaces.isEmpty) else { continue }

            // On the current desktop, only minimized windows can be off screen
            // in an app that isn't hidden. Don't ask apps that can't have any listed.
            guard options.allDesktops || app.isHidden || options.minimizedWindows != .hidden else { continue }

            // Minimized state only comes from Accessibility, so skip busy apps.
            let lookup = lookups[pid] ?? accessibilityWindows(of: pid)
            lookups[pid] = lookup
            // A window missing from Accessibility off screen is usually one the
            // app closed but kept, not an overlay, so it isn't marked rejected.
            guard case let .answered(axWindows) = lookup, let element = axWindows[id] else { continue }
            guard let attributes = AX.windowAttributes(of: element) else {
                // The app stopped answering. Don't wait on it for its other windows.
                lookups[pid] = .busy
                continue
            }
            guard Self.isSwitchable(subrole: attributes.subrole, title: attributes.title, size: bounds.size) else { continue }

            let state: WindowInfo.State
            if attributes.isMinimized {
                guard options.minimizedWindows != .hidden else { continue }
                state = .minimized
            } else if app.isHidden {
                guard options.hiddenAppWindows != .hidden else { continue }
                state = .appHidden
            } else if !onCurrentDesktop {
                state = .otherDesktop
            } else {
                // Off screen for another reason, such as a window being set up.
                continue
            }

            windows.append(WindowInfo(
                id: id,
                pid: pid,
                appName: app.localizedName ?? "",
                title: attributes.title,
                icon: app.icon,
                element: element,
                state: state
            ))
        }
        return windows
    }

    /// The basic checks every listed window passes: a normal window of a
    /// running app, not SpaceTab's own, on the chosen screen.
    private static func candidate(
        _ entry: [String: Any],
        options: ListingOptions
    ) -> (id: CGWindowID, pid: pid_t, bounds: CGRect, app: NSRunningApplication)? {
        guard
            (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
            let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            pid != getpid(),
            (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
            let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
            options.includes(bounds),
            let app = NSRunningApplication(processIdentifier: pid),
            app.activationPolicy != .prohibited,
            options.onlyPID.map({ $0 == pid }) ?? true,
            !options.excludedBundleIDs.contains(app.bundleIdentifier ?? "")
        else { return nil }
        return (id, pid, bounds, app)
    }

    /// Puts windows in most recently used order. `windows` is front to back,
    /// with off-screen windows last.
    ///
    /// A window missing from the history (its focus change was missed) is
    /// placed just in front of the next known window behind it on screen.
    /// Windows in an `atEnd` state go after all others.
    /// The window with keyboard focus comes first, unless a switch SpaceTab
    /// just made hasn't reached its app yet.
    static func order(
        _ windows: [WindowInfo],
        ranks: [CGWindowID: Int],
        focusedID: CGWindowID?,
        frontmostPID: pid_t?,
        pendingSwitch: PendingSwitch?,
        focusedElsewhere: Bool = false,
        atEnd: Set<WindowInfo.State> = [],
        groupByApp: Bool = false
    ) -> WindowList {
        var sortKeys = [(rank: Int, isKnown: Bool, offset: Int)](repeating: (0, false, 0), count: windows.count)
        // Only windows on screen have a place in front-to-back order, so only
        // they pass their rank to unknown windows in front of them.
        var rankBehind = Int.max
        for offset in windows.indices.reversed() {
            let isOnScreen = windows[offset].isOnScreen
            if let rank = ranks[windows[offset].id] {
                sortKeys[offset] = (rank, true, offset)
                if isOnScreen {
                    rankBehind = rank
                }
            } else {
                sortKeys[offset] = (isOnScreen ? rankBehind : Int.max, false, offset)
            }
        }
        var ordered = windows.indices
            .sorted { a, b in
                let (ka, kb) = (sortKeys[a], sortKeys[b])
                if ka.rank != kb.rank { return ka.rank < kb.rank }
                if ka.isKnown != kb.isKnown { return !ka.isKnown }
                return ka.offset < kb.offset
            }
            .map { windows[$0] }
        if !atEnd.isEmpty {
            // Stable: both groups keep their most recently used order.
            ordered = ordered.filter { !atEnd.contains($0.state) } + ordered.filter { atEnd.contains($0.state) }
        }
        if groupByApp {
            let front = ordered.filter { !atEnd.contains($0.state) }
            let back = ordered.filter { atEnd.contains($0.state) }
            ordered = grouped(front) + grouped(back)
        }

        if let pendingSwitch, pendingSwitch.pid != frontmostPID {
            // You are still on the way to that window: treat it as current.
            return WindowList(windows: ordered, firstIsCurrent: ordered.first?.id == pendingSwitch.id)
        }
        if let focusedID, let index = ordered.firstIndex(where: { $0.id == focusedID }), index > 0 {
            // A focus change may have been missed; the focused window is always current.
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return WindowList(
            windows: ordered,
            firstIsCurrent: !focusedElsewhere && frontmostPID != nil && ordered.first?.pid == frontmostPID
        )
    }

    /// Windows of the same app next to each other. Apps keep the order of
    /// their most recently used window, and windows keep their order within the app.
    static func grouped(_ windows: [WindowInfo]) -> [WindowInfo] {
        var pids: [pid_t] = []
        for window in windows where !pids.contains(window.pid) {
            pids.append(window.pid)
        }
        return pids.flatMap { pid in windows.filter { $0.pid == pid } }
    }

    /// Whether a window the app reports to Accessibility belongs in the switcher.
    /// Leaves out palettes, popups and notification balloons.
    static func isSwitchable(subrole: String?, title: String, size: CGSize) -> Bool {
        switch subrole {
        case kAXFloatingWindowSubrole, "AXSystemDialog":
            return false
        case kAXStandardWindowSubrole:
            return !title.isEmpty || isLargeEnough(size)
        case kAXDialogSubrole:
            return !title.isEmpty
        default:
            return !title.isEmpty && isLargeEnough(size)
        }
    }

    private static func isLargeEnough(_ size: CGSize) -> Bool {
        size.width >= 100 && size.height >= 50
    }

    private static func onScreenEntries() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private func accessibilityWindows(of pid: pid_t) -> Lookup {
        let (elements, busy) = AX.windows(of: pid)
        guard let elements else { return busy ? .busy : .unavailable }
        var result: [CGWindowID: AXUIElement] = [:]
        for element in elements {
            if let id = AX.windowID(of: element) {
                result[id] = element
            }
        }
        return .answered(result)
    }

    /// Keeps what answering apps reported, including windows on other desktops,
    /// and forgets windows that no longer exist.
    private func updateCache(
        lookups: [pid_t: Lookup],
        fresh: [pid_t: [CGWindowID: CachedWindow]],
        rejected: [pid_t: Set<CGWindowID>],
        examined: [pid_t: Set<CGWindowID>]
    ) {
        for (pid, lookup) in lookups {
            guard case .answered = lookup else { continue }
            var cache = lastKnown[pid] ?? [:]
            cache.merge(fresh[pid] ?? [:]) { $1 }
            for id in rejected[pid] ?? [] {
                cache[id] = nil
            }
            lastKnown[pid] = cache
            // Windows on other screens or desktops weren't looked at this
            // time, so what was known about them stays.
            lastRejected[pid] = (lastRejected[pid] ?? [])
                .subtracting(examined[pid] ?? [])
                .union(rejected[pid] ?? [])
        }

        let allIDs = Set(
            (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        )
        lastKnown = lastKnown.compactMapValues { windows in
            let existing = windows.filter { allIDs.contains($0.key) }
            return existing.isEmpty ? nil : existing
        }
        lastRejected = lastRejected.compactMapValues { ids in
            let existing = ids.intersection(allIDs)
            return existing.isEmpty ? nil : existing
        }
    }
}
