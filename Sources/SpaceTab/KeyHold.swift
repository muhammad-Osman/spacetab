import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Keys typed after ⌥ was released but before the switch finished. They are
/// replayed to the new window, so ⌥ Tab then ⌘W closes the right one.
@MainActor
final class KeyHold {
    /// Marks replayed key events, so the event tap lets them through.
    static let replayTag: Int64 = 0x5350_5442
    private static let maxEvents = 64
    /// How long to hold keys before giving them to whatever app is in front.
    private static let timeout: TimeInterval = 1.5
    private static let secureInputCheckInterval: TimeInterval = 0.015

    /// Nil when not holding.
    private var events: [CGEvent]?
    /// Keys whose key-down is in `events`. Only their repeats and releases are held.
    private var heldDown = Set<Int64>()
    /// Keys whose key-down went through during the hold. Their release goes through too.
    private var passedThrough = Set<Int64>()
    /// The app the switch goes to, once known.
    private var target: pid_t?
    private var systemShortcuts = Set<SystemShortcut>()
    /// Bumped each time holding starts or is extended, so only the latest timeout fires.
    private var holdCount = 0
    private var secureInputTimer: Timer?

    var isHolding: Bool { events != nil }

    /// Starts holding keys, or keeps holding them for the next step of the switch.
    func start(target: pid_t? = nil) {
        if let target {
            self.target = target
        }
        if events == nil {
            // Secure input hides key presses from the event tap, so holding
            // would only put the keys it does see out of order.
            guard !IsSecureEventInputEnabled() else { return }
            events = []
            systemShortcuts = SystemShortcut.enabled()
            secureInputTimer = Timer.scheduledTimer(withTimeInterval: Self.secureInputCheckInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    // The new app turned on secure input (a password field):
                    // the next keys go straight to it, so send the held ones first.
                    guard let self, IsSecureEventInputEnabled() else { return }
                    self.release(to: self.target)
                }
            }
        }

        holdCount += 1
        let holdCount = self.holdCount
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            guard let self, self.holdCount == holdCount else { return }
            self.release(to: nil)
        }
    }

    /// Holds a key event if it belongs to the switch. Returns `true` to
    /// swallow it, `false` to let it through to the app in front.
    /// `swallowedKeys` are keys the switcher itself used.
    func hold(_ event: CGEvent, type: CGEventType, keyCode: Int64, swallowedKeys: inout Set<Int64>) -> Bool {
        guard events != nil else { return false }

        if type == .keyUp {
            if swallowedKeys.remove(keyCode) != nil {
                return true
            }
            if passedThrough.remove(keyCode) != nil {
                return false
            }
            // A key pressed before the hold is released where it was pressed.
            guard heldDown.contains(keyCode) else { return false }
            // Always keep a held key's release, even over the limit, so it can't stay down.
            append(event)
            return true
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            // Repeats of Tab or an arrow still held from the switcher.
            if swallowedKeys.contains(keyCode) {
                return true
            }
            // Repeats of a key held in the previous app keep going there.
            guard heldDown.contains(keyCode) else { return false }
            if (events?.count ?? 0) < Self.maxEvents {
                append(event)
            }
            return true
        }

        guard
            !systemShortcuts.contains(SystemShortcut(keyCode: keyCode, flags: event.flags)),
            (events?.count ?? 0) < Self.maxEvents
        else {
            // System shortcuts only work as real key presses, not replayed ones.
            passedThrough.insert(keyCode)
            return false
        }
        append(event)
        heldDown.insert(keyCode)
        swallowedKeys.remove(keyCode)
        return true
    }

    /// Replays held keys: to the app with `pid`, or to whatever app is in front when nil.
    func release(to pid: pid_t?) {
        guard let events else { return }
        self.events = nil
        heldDown = []
        passedThrough = []
        target = nil
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    private func append(_ event: CGEvent) {
        if let copy = event.copy() {
            events?.append(copy)
        }
    }
}

/// A macOS keyboard shortcut from System Settings > Keyboard > Keyboard
/// Shortcuts, such as ⌘Space for Spotlight or ⌃Space for input sources.
struct SystemShortcut: Hashable {
    let keyCode: Int64
    /// Carbon modifier flags.
    let modifiers: UInt32

    private static let modifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    init(keyCode: Int64, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(keyCode: Int64, flags: CGEventFlags) {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    static func enabled() -> Set<SystemShortcut> {
        var list: Unmanaged<CFArray>?
        guard
            CopySymbolicHotKeys(&list) == noErr,
            let hotKeys = list?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return Set(hotKeys.compactMap { hotKey in
            guard
                (hotKey[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                let code = (hotKey[kHISymbolicHotKeyCode as String] as? NSNumber)?.int64Value,
                let modifiers = (hotKey[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value
            else { return nil }
            return SystemShortcut(keyCode: code, modifiers: modifiers)
        })
    }
}
