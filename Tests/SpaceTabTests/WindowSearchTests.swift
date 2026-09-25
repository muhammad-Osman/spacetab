import XCTest
@testable import SpaceTab

final class WindowSearchTests: XCTestCase {
    private func window(_ id: CGWindowID, _ title: String, app: String) -> WindowInfo {
        WindowInfo(id: id, pid: pid_t(id), appName: app, title: title, icon: nil, element: nil)
    }

    private let windows = [
        WindowInfo(id: 1, pid: 1, appName: "Terminal", title: "zsh — ~/alt_tab", icon: nil, element: nil),
        WindowInfo(id: 2, pid: 2, appName: "Visual Studio Code", title: "README.md — spacetab", icon: nil, element: nil),
        WindowInfo(id: 3, pid: 3, appName: "Safari", title: "Résumé tips", icon: nil, element: nil),
        WindowInfo(id: 4, pid: 4, appName: "Notes", title: "Code review", icon: nil, element: nil),
    ]

    func testEmptyQueryKeepsEverythingInOrder() {
        XCTAssertEqual(WindowSearch.filter(windows, query: "  ").map(\.id), [1, 2, 3, 4])
    }

    func testInitialsMatchTheAppName() {
        XCTAssertEqual(WindowSearch.filter(windows, query: "vsc").map(\.id), [2])
    }

    func testMatchIsCaseAndAccentInsensitive() {
        XCTAssertEqual(WindowSearch.filter(windows, query: "resume").map(\.id), [3])
        XCTAssertEqual(WindowSearch.filter(windows, query: "SAFARI").map(\.id), [3])
    }

    func testBetterMatchesComeFirst() {
        // "code" appears in both, but as a whole word at the start of a title in Notes.
        let ids = WindowSearch.filter(windows, query: "code").map(\.id)
        XCTAssertEqual(Set(ids), [2, 4])
        XCTAssertEqual(ids.first, 4)
    }

    func testNoMatchGivesEmptyList() {
        XCTAssertTrue(WindowSearch.filter(windows, query: "xyz").isEmpty)
    }

    func testCharactersMustAppearInOrder() {
        XCTAssertNil(WindowSearch.score("safari", query: "fs"))
        XCTAssertNotNil(WindowSearch.score("safari", query: "sf"))
    }
}
