import Carbon.HIToolbox
import Foundation

/// Makes the shortcuts work while an app has secure input on (a password
/// field, or Terminal's Secure Keyboard Entry). Secure input hides key
/// presses from the event tap, but system hot keys still fire.
///
/// The hot keys are registered all the time the tap runs. Normally the tap
/// sees the shortcut first and swallows it, and a swallowed key never
/// reaches the hot key, so nothing happens twice. The hot keys only act
/// under secure input. While the switcher is open that way, the arrow keys
/// and Esc are registered too, with the shortcut's modifiers.
@MainActor
final class HotKeyFallback {
    /// Called for a shortcut press under secure input. The flag means backwards (⇧).
    var onShortcut: ((Shortcut, Bool) -> Void)?
    /// Called for an arrow key or Esc while the switcher is open under secure input.
    var onNavigation: ((Int64) -> Void)?

    private struct Registration {
        let ref: EventHotKeyRef
        let shortcut: Shortcut?
        let backwards: Bool
        let keyCode: Int64
    }

    private static let signature = OSType(0x5354_6162) // "STab"
    private static let navigationKeys: [Int64] = [123, 124, 125, 126, 53]

    private var handler: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var shortcuts: [Shortcut] = []
    private var isRunning = false
    private var isPaused = false
    private var navigationModifiers: Shortcut.Modifiers?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyCallback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func start(shortcuts: [Shortcut]) {
        isRunning = true
        self.shortcuts = shortcuts
        apply()
    }

    func stop() {
        isRunning = false
        navigationModifiers = nil
        apply()
    }

    func update(shortcuts: [Shortcut]) {
        self.shortcuts = shortcuts
        apply()
    }

    /// While Settings records a shortcut, the keys must reach the recorder,
    /// which a hot key would prevent.
    func setPaused(_ paused: Bool) {
        isPaused = paused
        apply()
    }

    /// The switcher opened under secure input with this shortcut's modifiers held.
    func switcherOpened(modifiers: Shortcut.Modifiers) {
        navigationModifiers = modifiers
        apply()
    }

    func switcherClosed() {
        guard navigationModifiers != nil else { return }
        navigationModifiers = nil
        apply()
    }

    fileprivate func fired(_ id: UInt32) {
        // Without secure input the tap handles the key; a hot key only fires
        // then for a key the tap let through on purpose.
        guard IsSecureEventInputEnabled(), let registration = registrations[id] else { return }
        if let shortcut = registration.shortcut {
            onShortcut?(shortcut, registration.backwards)
        } else {
            onNavigation?(registration.keyCode)
        }
    }

    private func apply() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations = [:]
        guard isRunning, !isPaused else { return }

        for shortcut in shortcuts where !shortcut.modifiers.contains(.function) {
            // Hot keys can't include the Fn key.
            register(keyCode: shortcut.keyCode, modifiers: Self.carbonModifiers(shortcut.modifiers), shortcut: shortcut, backwards: false)
            register(keyCode: shortcut.keyCode, modifiers: Self.carbonModifiers(shortcut.modifiers) | UInt32(shiftKey), shortcut: shortcut, backwards: true)
        }
        if let navigationModifiers {
            for keyCode in Self.navigationKeys {
                register(keyCode: keyCode, modifiers: Self.carbonModifiers(navigationModifiers), shortcut: nil, backwards: false)
            }
        }
    }

    private func register(keyCode: Int64, modifiers: UInt32, shortcut: Shortcut?, backwards: Bool) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), modifiers, EventHotKeyID(signature: Self.signature, id: id), GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return }
        registrations[id] = Registration(ref: ref, shortcut: shortcut, backwards: backwards, keyCode: keyCode)
    }

    private static func carbonModifiers(_ modifiers: Shortcut.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

private func hotKeyCallback(_ handler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let fallback = Unmanaged<HotKeyFallback>.fromOpaque(userData).takeUnretainedValue()
    // Hot key events are delivered on the main run loop.
    MainActor.assumeIsolated { fallback.fired(hotKeyID.id) }
    return noErr
}
