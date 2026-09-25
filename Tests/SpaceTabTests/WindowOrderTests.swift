import XCTest
@testable import SpaceTab

final class WindowOrderTests: XCTestCase {
    private func window(_ id: CGWindowID, pid: pid_t, state: WindowInfo.State = .normal) -> WindowInfo {
        WindowInfo(id: id, pid: pid, appName: "App \(pid)", title: "Window \(id)", icon: nil, element: nil, state: state)
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

    func testMinimizedWindowsGoToTheEndWhenAsked() {
        // The minimized window (2) was used more recently than window 3.
        let onScreen = [window(1, pid: 10), window(3, pid: 30), window(2, pid: 20, state: .minimized)]
        let ranks: [CGWindowID: Int] = [1: 0, 2: 1, 3: 2]
        let mixed = WindowLister.order(onScreen, ranks: ranks, focusedID: 1, frontmostPID: 10, pendingSwitch: nil)
        XCTAssertEqual(ids(mixed), [1, 2, 3])
        let atEnd = WindowLister.order(
            onScreen, ranks: ranks, focusedID: 1, frontmostPID: 10, pendingSwitch: nil, atEnd: [.minimized]
        )
        XCTAssertEqual(ids(atEnd), [1, 3, 2])
    }

    func testHiddenAndMinimizedAtEndKeepTheirOrder() {
        let onScreen = [
            window(1, pid: 10),
            window(4, pid: 40, state: .appHidden),
            window(2, pid: 20, state: .minimized),
            window(3, pid: 30),
        ]
        let list = WindowLister.order(
            onScreen,
            ranks: [1: 0, 4: 1, 2: 2, 3: 3],
            focusedID: 1,
            frontmostPID: 10,
            pendingSwitch: nil,
            atEnd: [.minimized, .appHidden]
        )
        XCTAssertEqual(ids(list), [1, 3, 4, 2])
    }

    func testUnknownWindowIsNotRankedByAMinimizedWindow() {
        // On screen: A (0), K (2), U (never focused). Off screen: M (1), just minimized.
        let windows = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 30), window(4, pid: 40, state: .minimized)]
        let list = WindowLister.order(
            windows, ranks: [1: 0, 2: 2, 4: 1], focusedID: 1, frontmostPID: 10, pendingSwitch: nil, atEnd: [.minimized]
        )
        XCTAssertEqual(ids(list), [1, 2, 3, 4], "the quick flip must go to K, not the unknown window")
    }

    func testUnknownOffScreenWindowGoesLastWhenMixed() {
        // On screen: A (0), B (2). Off screen: H (hidden app, unknown), N (1, minimized).
        let windows = [
            window(1, pid: 10), window(2, pid: 20),
            window(3, pid: 30, state: .appHidden), window(4, pid: 40, state: .minimized),
        ]
        let list = WindowLister.order(windows, ranks: [1: 0, 2: 2, 4: 1], focusedID: 1, frontmostPID: 10, pendingSwitch: nil)
        XCTAssertEqual(ids(list), [1, 4, 2, 3])
    }

    func testFirstIsNotCurrentWhenTheFocusedWindowIsOnAnotherScreen() {
        // Safari's focused window is on another screen; Safari's window S here is just the most recent.
        let windows = [window(2, pid: 10), window(3, pid: 20)]
        let list = WindowLister.order(
            windows, ranks: [2: 0, 3: 1], focusedID: 1, frontmostPID: 10, pendingSwitch: nil, focusedElsewhere: true
        )
        XCTAssertFalse(list.firstIsCurrent, "the quick flip must go to S, the newest window on this screen")
    }

    func testGroupingKeepsAppsInOrderOfTheirMostRecentWindow() {
        let windows = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 10), window(4, pid: 30), window(5, pid: 20)]
        XCTAssertEqual(WindowLister.grouped(windows).map(\.id), [1, 3, 2, 5, 4])
    }

    func testGroupingDoesNotPullMinimizedWindowsForward() {
        let windows = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 10, state: .minimized)]
        let list = WindowLister.order(
            windows, ranks: [1: 0, 2: 1, 3: 2], focusedID: 1, frontmostPID: 10, pendingSwitch: nil,
            atEnd: [.minimized], groupByApp: true
        )
        XCTAssertEqual(ids(list), [1, 2, 3])
    }
}
