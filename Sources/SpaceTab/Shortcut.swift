import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Which windows a shortcut switches between.
enum ShortcutScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case currentDesktop
    case allDesktops
    case currentApp

    var id: Self { self }

    var title: String {
        switch self {
        case .currentDesktop: "Windows on the current desktop"
        case .allDesktops: "Windows on all desktops"
        case .currentApp: "Windows of the current app"
        }
    }
}

/// A key combination that opens the switcher. Holding the modifiers keeps it
/// open; letting go of any of them switches.
struct Shortcut: Codable, Equatable, Identifiable, Sendable {
    static let maxCount = 9
    static let defaults = [
        Shortcut(keyCode: 48, modifiers: .option, scope: .currentDesktop),
        Shortcut(keyCode: 48, modifiers: [.control, .option], scope: .allDesktops),
    ]

    /// The modifiers a shortcut can use. Shift is not one: with the shortcut
    /// held, shift moves backwards.
    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt8

        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let command = Modifiers(rawValue: 4)
        static let function = Modifiers(rawValue: 8)

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// The modifiers held in `flags`. Arrow, navigation and function
        /// keys always carry the Fn flag, so for them it doesn't count.
        init(flags: CGEventFlags, keyCode: Int64? = nil) {
            var modifiers = Modifiers()
            if flags.contains(.maskControl) { modifiers.insert(.control) }
            if flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if flags.contains(.maskCommand) { modifiers.insert(.command) }
            if flags.contains(.maskSecondaryFn), !(keyCode.map(Shortcut.keysThatCarryFn.contains) ?? false) {
                modifiers.insert(.function)
            }
            self = modifiers
        }

        var symbols: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.command) { text += "⌘" }
            if contains(.function) { text += "fn" }
            return text
        }
    }

    /// Keys whose events carry the Fn flag whether or not the Globe key is held.
    static let keysThatCarryFn: Set<Int64> = [
        123, 124, 125, 126, 115, 116, 117, 119, 121, 114,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    var id = UUID()
    var keyCode: Int64
    var modifiers: Modifiers
    var scope: ShortcutScope

    init(keyCode: Int64, modifiers: Modifiers, scope: ShortcutScope) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.scope = scope
    }

    /// Whether this key press is the shortcut. Shift is allowed (it means
    /// backwards); any other extra modifier means a different shortcut.
    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && Modifiers(flags: flags, keyCode: keyCode) == modifiers
    }

    /// Whether every modifier of the shortcut is held. The Fn key doesn't
    /// count: macOS doesn't report it reliably, so it can't end the switcher.
    func isHeld(in flags: CGEventFlags) -> Bool {
        Modifiers(flags: flags).isSuperset(of: modifiers.subtracting(.function))
    }

    var displayText: String {
        modifiers.symbols + " " + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: Int64) -> String {
        if let name = specialKeyNames[keyCode] {
            return name
        }
        return MainActor.assumeIsolated { KeyTranslator.character(keyCode: keyCode, shift: false) }?.uppercased()
            ?? "Key \(keyCode)"
    }

    private static let specialKeyNames: [Int64: String] = [
        48: "Tab", 49: "Space", 36: "Return", 76: "Enter", 53: "Esc", 51: "Delete", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 50: "`",
    ]
}

/// The shortcuts in UserDefaults.
enum ShortcutSettings {
    static let key = "shortcuts"
    /// True while a recorder in Settings waits for a key. The event tap then
    /// lets every key through, so pressing ⌥ Tab records it instead of
    /// opening the switcher.
    @MainActor static var isRecording = false
    /// Posted after the shortcuts change.
    static let changed = Notification.Name("SpaceTabShortcutsChanged")

    static func load(from defaults: UserDefaults = .standard) -> [Shortcut] {
        guard
            let data = defaults.data(forKey: key),
            let shortcuts = try? JSONDecoder().decode([Shortcut].self, from: data)
        else { return Shortcut.defaults }
        return shortcuts
    }

    static func save(_ shortcuts: [Shortcut], to defaults: UserDefaults = .standard) {
        let kept = Array(shortcuts.prefix(Shortcut.maxCount))
        if let data = try? JSONEncoder().encode(kept) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
