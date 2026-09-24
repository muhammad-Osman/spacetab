import XCTest
@testable import SpaceTab

final class SwitcherSelectionTests: XCTestCase {
    func testOpeningForwardsSelectsPreviousWindow() {
        XCTAssertEqual(SwitcherSelection(count: 5, openingBackwards: false).index, 1)
    }

    func testOpeningForwardsWithOneWindowSelectsIt() {
        XCTAssertEqual(SwitcherSelection(count: 1, openingBackwards: false).index, 0)
    }

    func testOpeningForwardsWhenFirstIsNotCurrentSelectsFirst() {
        XCTAssertEqual(SwitcherSelection(count: 3, openingBackwards: false, firstIsCurrent: false).index, 0)
        XCTAssertEqual(SwitcherSelection(count: 1, openingBackwards: false, firstIsCurrent: false).index, 0)
    }

    func testOpeningBackwardsSelectsLastWindow() {
        XCTAssertEqual(SwitcherSelection(count: 5, openingBackwards: true).index, 4)
        XCTAssertEqual(SwitcherSelection(count: 5, openingBackwards: true, firstIsCurrent: false).index, 4)
    }

    func testMovingWrapsAroundBothEnds() {
        var selection = SwitcherSelection(count: 3, openingBackwards: true)
        selection.move(by: 1)
        XCTAssertEqual(selection.index, 0)
        selection.move(by: -1)
        XCTAssertEqual(selection.index, 2)
        selection.move(by: -7)
        XCTAssertEqual(selection.index, 1)
    }

    func testMovingWithNoWindowsDoesNothing() {
        var selection = SwitcherSelection(count: 0, openingBackwards: false)
        selection.move(by: 1)
        XCTAssertEqual(selection.index, 0)
    }
}
