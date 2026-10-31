import XCTest
@testable import SpaceTab

final class WindowListReconcilerTests: XCTestCase {
    private func window(_ id: CGWindowID, title: String = "Window", state: WindowInfo.State = .normal) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "App", title: title, icon: nil, element: nil, state: state)
    }

    func testUnchangedListDoesNotRedraw() {
        let shown = [window(1), window(2)]
        let result = WindowListReconciler.reconcile(shown: shown, fresh: shown, selectedID: 2)
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.selectedIndex, 1)
    }

    func testTitleChangeRedraws() {
        let result = WindowListReconciler.reconcile(shown: [window(1)], fresh: [window(1, title: "Renamed")], selectedID: 1)
        XCTAssertTrue(result.changed)
    }

    func testClosedSelectedWindowClampsToNearestIndex() {
        let result = WindowListReconciler.reconcile(shown: [window(1), window(2), window(3)], fresh: [window(1), window(2)], selectedID: 3)
        XCTAssertEqual(result.selectedIndex, 1)
    }

    func testSelectionSurvivesReorder() {
        let result = WindowListReconciler.reconcile(shown: [window(1), window(2)], fresh: [window(2), window(1)], selectedID: 2)
        XCTAssertEqual(result.selectedIndex, 0)
    }

    func testEmptyFreshListIsChangedAndHasSafeSelection() {
        let result = WindowListReconciler.reconcile(shown: [window(1)], fresh: [], selectedID: 1)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.selectedIndex, 0)
    }
}
