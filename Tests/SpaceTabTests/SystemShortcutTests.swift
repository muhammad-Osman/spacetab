import Carbon.HIToolbox
import XCTest
@testable import SpaceTab

final class SystemShortcutTests: XCTestCase {
    private let fn = UInt32(kEventKeyModifierFnMask)

    func testPlainLettersDoNotMatchGlobeShortcuts() {
        // Globe + A is in the system list; a plain A must not look like it.
        let globeA = SystemShortcut(keyCode: 0, modifiers: fn)
        XCTAssertNotEqual(SystemShortcut(keyCode: 0, flags: []), globeA)
        XCTAssertEqual(SystemShortcut(keyCode: 0, flags: .maskSecondaryFn), globeA)
    }

    func testControlCDoesNotMatchControlGlobeC() {
        let controlGlobeC = SystemShortcut(keyCode: 8, modifiers: UInt32(controlKey) | fn)
        XCTAssertNotEqual(SystemShortcut(keyCode: 8, flags: .maskControl), controlGlobeC)
    }

    func testArrowShortcutsWithOnlyGlobeAreLeftOut() {
        // Arrow key events always carry the Fn flag, so this entry would match every ← press.
        XCTAssertFalse(SystemShortcut(keyCode: 123, modifiers: fn).isDistinguishable)
        XCTAssertTrue(SystemShortcut(keyCode: 123, modifiers: UInt32(controlKey) | fn).isDistinguishable)
        XCTAssertTrue(SystemShortcut(keyCode: 103, modifiers: fn).isDistinguishable, "F11 with Fn stays")
    }

    func testControlLeftMatchesMoveLeftASpace() {
        let moveLeft = SystemShortcut(keyCode: 123, modifiers: UInt32(controlKey) | fn)
        XCTAssertEqual(SystemShortcut(keyCode: 123, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad]), moveLeft)
        XCTAssertNotEqual(SystemShortcut(keyCode: 123, flags: [.maskSecondaryFn, .maskNumericPad]), moveLeft)
    }

    func testCapsLockIsIgnored() {
        let spotlight = SystemShortcut(keyCode: 49, modifiers: UInt32(cmdKey))
        XCTAssertEqual(SystemShortcut(keyCode: 49, flags: [.maskCommand, .maskAlphaShift]), spotlight)
    }
}
