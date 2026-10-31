import AppKit

/// A short-lived raw window list. Ordering it with current history is cheap;
/// asking every app for Accessibility attributes is not.
@MainActor
final class WindowListCache {
    private static let maximumAge: TimeInterval = 10

    private var rawWindows: [WindowInfo] = []
    private var spaceIDs: Set<UInt64>?
    private var options: ListingOptions?
    private var timestamp: Date?
    private var focusedElsewhere = false

    func store(_ list: WindowList, options: ListingOptions) {
        guard let spaceIDs = Spaces.currentSpaceIDs() else { return }
        rawWindows = list.rawWindows
        self.spaceIDs = spaceIDs
        self.options = options
        timestamp = Date()
        focusedElsewhere = list.focusedElsewhere
    }

    func usable(options: ListingOptions) -> (windows: [WindowInfo], focusedElsewhere: Bool)? {
        guard let timestamp, Date().timeIntervalSince(timestamp) < Self.maximumAge,
              self.options == options,
              let spaceIDs, spaceIDs == Spaces.currentSpaceIDs()
        else { return nil }
        return (rawWindows, focusedElsewhere)
    }

    func invalidate() {
        timestamp = nil
        rawWindows = []
        spaceIDs = nil
        options = nil
    }
}

enum WindowListReconciler {
    static func reconcile(shown: [WindowInfo], fresh: [WindowInfo], selectedID: CGWindowID?) -> (windows: [WindowInfo], selectedIndex: Int, changed: Bool) {
        let changed = shown.count != fresh.count || zip(shown, fresh).contains {
            $0.id != $1.id || $0.title != $1.title || $0.state != $1.state
        }
        guard !fresh.isEmpty else { return (fresh, 0, changed) }
        let oldIndex = selectedID.flatMap { id in shown.firstIndex { $0.id == id } } ?? 0
        let selectedIndex = selectedID.flatMap { id in fresh.firstIndex { $0.id == id } }
            ?? min(oldIndex, fresh.count - 1)
        return (fresh, selectedIndex, changed)
    }
}
