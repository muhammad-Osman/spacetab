import Carbon.HIToolbox
import Foundation

/// Turns a key code into the character it types on the current keyboard
/// layout, ignoring ⌥. The switcher is used with ⌥ held, which would
/// otherwise turn letters into symbols (⌥S types ß).
@MainActor
enum KeyTranslator {
    /// Nil for keys that don't type a printable character.
    static func character(keyCode: Int64, shift: Bool) -> String? {
        character(keyCode: keyCode, shift: shift, layout: keyboardLayoutData())
    }

    /// The character on a Latin layout, for keys like W or / that mean an
    /// action whatever the letters on the keys say. Nil when the current
    /// layout is Latin already.
    static func asciiCharacter(keyCode: Int64, shift: Bool) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            !CFEqual(source, current)
        else { return nil }
        return character(keyCode: keyCode, shift: shift, layout: layoutData(of: source))
    }

    private static func character(keyCode: Int64, shift: Bool, layout: Data?) -> String? {
        guard let layout else { return nil }
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let modifiers = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
        let status = layout.withUnsafeBytes { buffer -> OSStatus in
            guard let keyboard = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                keyboard,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        let isPrintable = string.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        return isPrintable ? string : nil
    }

    /// The current layout, or the last Latin one when an input method (such
    /// as Japanese) is active and has no layout of its own.
    private static func keyboardLayoutData() -> Data? {
        for copySource in [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
            if let source = copySource()?.takeRetainedValue(), let data = layoutData(of: source) {
                return data
            }
        }
        return nil
    }

    private static func layoutData(of source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }
}
