import XCTest
@testable import SpaceTab

final class WindowOrderTests: XCTestCase {
    private func window(_ id: CGWindowID, pid: pid_t) -> WindowInfo {
        WindowInfo(id: id, pid: pid, appName: "App \(pid)", title: "Window \(id)", icon: nil, element: nil)
    }

    private func ids(_ list: WindowList) -> [CGWindowID] {
        list.windows.map(\.id)
    }

    func testSortsByHistoryNotScreenOrder() {
        // ⌘ Tab to Safari brought both of its windows forward: S1, S2, then Terminal.
        let onScreen = [window(1, pid: 10), window(2, pid: 10), window(3, pid: 20)]
        let list = WindowLister.order(onScreen, ranks: [1: 0, 3: 1, 2: 2], focusedID: 1, frontmostPID: 10, pendingSwitch: nil)
        XCTAssertEqual(ids(list), [1, 3, 2], "the quick flip must go back to Terminal, not Safari's other window")
        XCTAssertTrue(list.firstIsCurrent)
    }

    func testUnknownWindowGoesInFrontOfTheNextKnownWindowBehindIt() {
        // The focus change to X (id 2) was missed: S is known, X is not, T is behind X.
        let onScreen = [window(1, pid: 10), window(2, pid: 30), window(3, pid: 20)]
        let list = WindowLister.order(onScreen, ranks: [1: 0, 3: 1], focusedID: 1, frontmostPID: 10, pendingSwitch: nil)
        XCTAssertEqual(ids(list), [1, 2, 3])
    }

    func testUnknownWindowsWithNothingKnownBehindKeepScreenOrderAtTheEnd() {
        let onScreen = [window(4, pid: 10), window(1, pid: 20), window(5, pid: 30), window(6, pid: 40)]
        let list = WindowLister.order(onScreen, ranks: [1: 0], focusedID: nil, frontmostPID: 20, pendingSwitch: nil)
        XCTAssertEqual(ids(list), [4, 1, 5, 6])
    }

    func testFocusedWindowComesFirst() {
        let onScreen = [window(1, pid: 10), window(2, pid: 20)]
        let list = WindowLister.order(onScreen, ranks: [1: 0, 2: 1], focusedID: 2, frontmostPID: 20, pendingSwitch: nil)
        XCTAssertEqual(ids(list), [2, 1])
        XCTAssertTrue(list.firstIsCurrent)
    }

    func testFirstIsNotCurrentWhenTheAppInFrontHasNoWindow() {
        let onScreen = [window(1, pid: 10), window(2, pid: 20)]
        let list = WindowLister.order(onScreen, ranks: [1: 0, 2: 1], focusedID: nil, frontmostPID: 99, pendingSwitch: nil)
        XCTAssertFalse(list.firstIsCurrent)
    }

    func testPendingSwitchCountsAsCurrentBeforeItsAppIsInFront() {
        // Switched from Terminal (pid 20) to W (pid 30), whose app isn't in front yet.
        let onScreen = [window(2, pid: 20), window(3, pid: 30)]
        let list = WindowLister.order(
            onScreen,
            ranks: [3: 0, 2: 1],
            focusedID: 2,
            frontmostPID: 20,
            pendingSwitch: PendingSwitch(id: 3, pid: 30)
        )
        XCTAssertEqual(ids(list), [3, 2], "the stale focused window must not jump ahead")
        XCTAssertTrue(list.firstIsCurrent)
    }
}
