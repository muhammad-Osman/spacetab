import CoreGraphics

/// Watches every key press in the system with a `CGEventTap`.
///
/// Each event goes to `onEvent`, which returns `true` to swallow it, so the
/// app in front never sees keys meant for the switcher.
@MainActor
final class HotKeyMonitor {
    typealias Handler = @MainActor (CGEventType, CGEvent) -> Bool

    private let onEvent: Handler
    private var tap: CFMachPort?

    var isRunning: Bool { tap != nil }

    init(onEvent: @escaping Handler) {
        self.onEvent = onEvent
    }

    /// Installs the event tap. Fails when Accessibility permission is missing.
    func start() -> Bool {
        if isRunning { return true }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns the tap off if a callback is slow; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        default:
            return onEvent(type, event)
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated { monitor.handle(type, event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
