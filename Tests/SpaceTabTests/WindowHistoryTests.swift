import XCTest
@testable import SpaceTab

@MainActor
final class WindowHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testFocusRanksMostRecentFirst() {
        let history = WindowHistory()
        history.focused(1, pid: 10, now: start)
        history.focused(2, pid: 20, now: start)
        history.focused(1, pid: 10, now: start)
        XCTAssertEqual(history.ranks(), [1: 0, 2: 1])
    }

    func testPromoteMovesWindowsInFrontKeepingTheirOrder() {
        let history = WindowHistory()
        history.focused(5, pid: 1, now: start)
        history.focused(6, pid: 1, now: start)
        history.promote([7, 5])
        XCTAssertEqual(history.ranks(), [7: 0, 5: 1, 6: 2])
    }

    func testBriefFocusOfAnotherWindowDuringSwitchIsIgnored() {
        let history = WindowHistory()
        history.focused(2, pid: 20, now: start)     // Chrome C1, used earlier
        history.focused(1, pid: 10, now: start)     // Terminal, where you are now
        history.switched(to: 3, pid: 20, now: start) // switch to Chrome C2
        history.focused(2, pid: 20, now: start.addingTimeInterval(0.1)) // C1 flickers
        XCTAssertEqual(history.ranks()[3], 0)
        XCTAssertEqual(history.ranks()[2], 2, "C1 must stay behind the window you came from")
    }

    func testFocusChangesCountAgainAfterTheSwitchSettles() {
        let history = WindowHistory()
        history.switched(to: 3, pid: 20, now: start)
        history.focused(2, pid: 20, now: start.addingTimeInterval(1))
        XCTAssertEqual(history.ranks()[2], 0)
    }

    func testFocusInOtherAppsCountsDuringSwitch() {
        let history = WindowHistory()
        history.switched(to: 3, pid: 20, now: start)
        history.focused(9, pid: 30, now: start.addingTimeInterval(0.1))
        XCTAssertEqual(history.ranks()[9], 0)
    }

    func testHistoryIsCapped() {
        let history = WindowHistory()
        for id in 1...600 {
            history.focused(CGWindowID(id), pid: 1, now: start)
        }
        let ranks = history.ranks()
        XCTAssertEqual(ranks.count, 500)
        XCTAssertEqual(ranks[600], 0)
        XCTAssertNil(ranks[1])
    }
}
