import CoreGraphics
import Foundation

/// A switch SpaceTab just made, while the target app may not be in front yet.
struct PendingSwitch {
    let id: CGWindowID
    let pid: pid_t
}

/// Window IDs in most recently used order, most recent first, across all desktops.
@MainActor
final class WindowHistory {
    private static let limit = 500
    /// How long after a switch focus changes in the target app are ignored.
    static let settleTime: TimeInterval = 0.6

    private var order: [CGWindowID] = []
    /// The window SpaceTab just switched to. While its app activates, it can
    /// briefly focus its previous window, which must not count as used.
    private var expected: (id: CGWindowID, pid: pid_t, until: Date)?

    /// Records a switch made with SpaceTab.
    func switched(to id: CGWindowID, pid: pid_t, now: Date = Date()) {
        moveToFront(id)
        expected = (id, pid, now.addingTimeInterval(Self.settleTime))
    }

    /// Records that a window got keyboard focus. Returns false when it was
    /// ignored because a switch to another window of that app is settling.
    @discardableResult
    func focused(_ id: CGWindowID, pid: pid_t, now: Date = Date()) -> Bool {
        if let expected, now < expected.until, expected.pid == pid, expected.id != id {
            return false
        }
        moveToFront(id)
        return true
    }

    /// The switch SpaceTab just made, while it is still settling.
    func pendingSwitch(now: Date = Date()) -> PendingSwitch? {
        guard let expected, now < expected.until else { return nil }
        return PendingSwitch(id: expected.id, pid: expected.pid)
    }

    /// Moves these windows in front of all others, keeping their order.
    /// `ids` is front to back.
    func promote(_ ids: [CGWindowID]) {
        let promoted = Set(ids)
        order.removeAll { promoted.contains($0) }
        order.insert(contentsOf: ids, at: 0)
        trim()
    }

    /// The position of each known window: 0 is the most recent.
    func ranks() -> [CGWindowID: Int] {
        Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func moveToFront(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        trim()
    }

    private func trim() {
        if order.count > Self.limit {
            order.removeLast(order.count - Self.limit)
        }
    }
}
