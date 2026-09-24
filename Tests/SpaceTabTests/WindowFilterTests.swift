import ApplicationServices
import XCTest
@testable import SpaceTab

final class WindowFilterTests: XCTestCase {
    private let large = CGSize(width: 800, height: 600)
    private let small = CGSize(width: 60, height: 30)

    func testStandardWindowsAreSwitchable() {
        XCTAssertTrue(WindowLister.isSwitchable(subrole: kAXStandardWindowSubrole, title: "Notes", size: large))
        XCTAssertTrue(WindowLister.isSwitchable(subrole: kAXStandardWindowSubrole, title: "", size: large))
    }

    func testSmallUntitledWindowsAreLeftOut() {
        XCTAssertFalse(WindowLister.isSwitchable(subrole: kAXStandardWindowSubrole, title: "", size: small))
        XCTAssertFalse(WindowLister.isSwitchable(subrole: nil, title: "", size: large))
    }

    func testFloatingWindowsAreLeftOut() {
        XCTAssertFalse(WindowLister.isSwitchable(subrole: kAXFloatingWindowSubrole, title: "Colors", size: large))
        XCTAssertFalse(WindowLister.isSwitchable(subrole: "AXSystemDialog", title: "Alert", size: large))
    }

    func testDialogsNeedATitle() {
        XCTAssertTrue(WindowLister.isSwitchable(subrole: kAXDialogSubrole, title: "Export", size: small))
        XCTAssertFalse(WindowLister.isSwitchable(subrole: kAXDialogSubrole, title: "", size: large))
    }

    func testOtherSubrolesNeedATitleAndSize() {
        XCTAssertTrue(WindowLister.isSwitchable(subrole: "AXUnknown", title: "Console", size: large))
        XCTAssertFalse(WindowLister.isSwitchable(subrole: "AXUnknown", title: "Console", size: small))
    }
}
