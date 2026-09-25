import Carbon.HIToolbox
import Foundation

/// Turns a key code into the character it types on the current keyboard
/// layout, ignoring ⌥. The switcher is used with ⌥ held, which would
/// otherwise turn letters into symbols (⌥S types ß).
@MainActor
enum KeyTranslator {
    /// Nil for keys that don't type a printable character.
    static func character(keyCode: Int64, shift: Bool) -> String? {
        guard let layout = keyboardLayoutData() else { return nil }
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
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
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
            guard
                let source = copySource()?.takeRetainedValue(),
                let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { continue }
            return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        }
        return nil
    }
}
