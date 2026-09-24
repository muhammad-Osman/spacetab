import XCTest
@testable import SpaceTab

final class ScreenChoiceTests: XCTestCase {
    // Two 1000x800 screens side by side, in CoreGraphics coordinates.
    private let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]

    func testWindowBelongsToTheScreenShowingMostOfIt() {
        let bounds = CGRect(x: 900, y: 100, width: 400, height: 300)
        XCTAssertEqual(ListingOptions.screenIndex(of: bounds, screens: screens), 1)
    }

    func testWindowHangingOffTheEdgeStillBelongsToItsScreen() {
        // More than half of it is past the right edge of the right screen.
        let bounds = CGRect(x: 1800, y: 100, width: 600, height: 300)
        XCTAssertEqual(ListingOptions.screenIndex(of: bounds, screens: screens), 1)
    }

    func testWindowOnNoScreenBelongsToTheNearest() {
        let bounds = CGRect(x: 2500, y: 100, width: 200, height: 200)
        XCTAssertEqual(ListingOptions.screenIndex(of: bounds, screens: screens), 1)
    }

    func testIncludesOnlyTheChosenScreen() {
        var options = ListingOptions(minimizedWindows: .atEnd, hiddenAppWindows: .atEnd, screens: screens, onlyScreen: 0)
        XCTAssertTrue(options.includes(CGRect(x: 100, y: 100, width: 300, height: 300)))
        XCTAssertFalse(options.includes(CGRect(x: 1100, y: 100, width: 300, height: 300)))
        options.onlyScreen = nil
        XCTAssertTrue(options.includes(CGRect(x: 1100, y: 100, width: 300, height: 300)))
    }
}
