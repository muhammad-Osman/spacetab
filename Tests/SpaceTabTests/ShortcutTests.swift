import XCTest
@testable import SpaceTab

final class ShortcutTests: XCTestCase {
    private let optionTab = Shortcut(keyCode: 48, modifiers: .option, scope: .currentDesktop)

    func testMatchesTheKeyWithExactlyItsModifiers() {
        XCTAssertTrue(optionTab.matches(keyCode: 48, flags: .maskAlternate))
        XCTAssertTrue(optionTab.matches(keyCode: 48, flags: [.maskAlternate, .maskShift]), "shift means backwards")
        XCTAssertFalse(optionTab.matches(keyCode: 48, flags: [.maskAlternate, .maskControl]))
        XCTAssertFalse(optionTab.matches(keyCode: 48, flags: .maskCommand))
        XCTAssertFalse(optionTab.matches(keyCode: 49, flags: .maskAlternate))
    }

    func testCapsLockAndNumericPadFlagsAreIgnored() {
        XCTAssertTrue(optionTab.matches(keyCode: 48, flags: [.maskAlternate, .maskAlphaShift, .maskNumericPad]))
    }

    func testIsHeldNeedsEveryModifier() {
        let controlOption = Shortcut(keyCode: 48, modifiers: [.control, .option], scope: .allDesktops)
        XCTAssertTrue(controlOption.isHeld(in: [.maskControl, .maskAlternate]))
        XCTAssertTrue(controlOption.isHeld(in: [.maskControl, .maskAlternate, .maskShift]))
        XCTAssertFalse(controlOption.isHeld(in: .maskAlternate))
        XCTAssertFalse(controlOption.isHeld(in: []))
    }

    func testDisplayText() {
        XCTAssertEqual(optionTab.displayText, "⌥ Tab")
        XCTAssertEqual(Shortcut(keyCode: 50, modifiers: .command, scope: .currentApp).displayText, "⌘ `")
        XCTAssertEqual(Shortcut(keyCode: 123, modifiers: [.control, .option, .command], scope: .allDesktops).displayText, "⌃⌥⌘ ←")
    }

    func testShortcutsSurviveEncoding() throws {
        let data = try JSONEncoder().encode(Shortcut.defaults)
        let decoded = try JSONDecoder().decode([Shortcut].self, from: data)
        XCTAssertEqual(decoded, Shortcut.defaults)
    }
}
