import AppKit

private enum KeyCode {
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
}

/// Decides what each key press does and drives the switcher.
///
/// The event tap holds up every key press on the Mac until its callback
/// returns, so the callback only updates state. Listing windows and switching
/// to one wait on other apps, so they run on background queues.
@MainActor
final class SwitcherController {
    private enum Phase {
        case idle
        /// ⌥ Tab was pressed and the window list is being built. Tab and arrow
        /// presses and the ⌥ release are recorded and applied when it arrives.
        case loading(backwards: Bool, moves: Int, released: Bool)
        case open(SwitcherSelection)
    }

    /// Marks key events SpaceTab replays, so the tap lets them through.
    private static let replayTag: Int64 = 0x5350_5442
    private static let maxHeldEvents = 64
    /// How long to wait for the window list after ⌥ was released before giving up.
    private static let loadingTimeout: TimeInterval = 0.5
    /// How long to hold keys for a switch before giving them to whatever app is in front.
    private static let holdTimeout: TimeInterval = 1

    private let history: WindowHistory
    private let panel = SwitcherPanel()
    private let lister = WindowLister()
    private let activator = WindowActivator()
    private let listingQueue = DispatchQueue(label: "SpaceTab.listing", qos: .userInteractive)

    private var phase = Phase.idle
    private var windows: [WindowInfo] = []
    /// Bumped on every open and cancel, so a window list that arrives late is ignored.
    private var generation = 0
    /// The app in front when the switcher opened.
    private var openedFromPID: pid_t?
    /// Keys whose key-down was swallowed. Their key-up is swallowed too, and
    /// only theirs, so no app sees a release without a press or misses one.
    private var swallowedKeys = Set<Int64>()
    /// Keys typed after ⌥ was released but before the switch finished. They
    /// are replayed to the new window, so ⌥ Tab then ⌘W closes the right one.
    /// Nil when not holding keys.
    private var heldEvents: [CGEvent]?
    /// Bumped for each switch, so only the latest switch releases held keys.
    private var switchCount = 0
    /// Bumped each time holding starts or is extended, so only the latest hold times out.
    private var holdCount = 0

    init(history: WindowHistory) {
        self.history = history
    }

    /// Whether key presses go to the switcher instead of the app in front.
    private var isCapturingKeys: Bool {
        switch phase {
        case .idle: false
        case .loading(_, _, let released): !released
        case .open: true
        }
    }

    /// Handles one keyboard event. Returns `true` to swallow it.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayTag {
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch type {
        case .flagsChanged:
            if !flags.contains(.maskAlternate) {
                optionReleased()
            }
            return false

        case .keyDown, .keyUp:
            if heldEvents != nil {
                let startsNewSwitch = type == .keyDown && keyCode == KeyCode.tab && isSwitcherShortcut(flags)
                if !startsNewSwitch {
                    return hold(event, type: type, keyCode: keyCode)
                }
                releaseHeldEvents(to: nil)
            }
            return type == .keyDown
                ? handleKeyDown(event, keyCode: keyCode, flags: flags)
                : handleKeyUp(keyCode: keyCode, flags: flags)

        default:
            return false
        }
    }

    /// Closes the switcher without switching.
    func cancel() {
        generation += 1
        close()
        releaseHeldEvents(to: nil)
    }

    /// Cancels and forgets all key state. Call when the event tap is removed or replaced.
    func reset() {
        cancel()
        swallowedKeys.removeAll()
    }

    /// Called after macOS turned the tap off and SpaceTab turned it back on.
    /// Key events went past the tap meanwhile, so the recorded state may be stale.
    func tapReenabled() {
        swallowedKeys.removeAll()
        if isCapturingKeys, !CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) {
            cancel()
        }
    }

    // MARK: - Keys

    private func handleKeyDown(_ event: CGEvent, keyCode: Int64, flags: CGEventFlags) -> Bool {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat {
            // A new press means the earlier release happened where the tap couldn't see it.
            swallowedKeys.remove(keyCode)
        }
        if isCapturingKeys, !flags.contains(.maskAlternate) {
            // The ⌥ release was missed, for example while macOS had the tap
            // turned off. Give the keyboard back instead of eating keys.
            cancel()
        }
        if isRepeat, !swallowedKeys.contains(keyCode) {
            // A key held down in an app keeps going to that app, even if ⌥ is added.
            return false
        }
        if keyCode == KeyCode.tab, isSwitcherShortcut(flags) {
            swallowedKeys.insert(keyCode)
            let backwards = flags.contains(.maskShift)
            if isCapturingKeys {
                move(by: backwards ? -1 : 1)
            } else {
                open(backwards: backwards)
            }
            return true
        }
        guard isCapturingKeys else {
            // Repeats of a key held since the switcher closed.
            return isRepeat
        }
        swallowedKeys.insert(keyCode)
        switch keyCode {
        case KeyCode.left, KeyCode.up: move(by: -1)
        case KeyCode.right, KeyCode.down: move(by: 1)
        case KeyCode.escape: cancel()
        default: break
        }
        return true
    }

    private func handleKeyUp(keyCode: Int64, flags: CGEventFlags) -> Bool {
        if swallowedKeys.remove(keyCode) != nil {
            return true
        }
        if isCapturingKeys, !flags.contains(.maskAlternate) {
            cancel()
        }
        return false
    }

    private func isSwitcherShortcut(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl)
    }

    // MARK: - Held keys

    private func hold(_ event: CGEvent, type: CGEventType, keyCode: Int64) -> Bool {
        // The release of a key the switcher swallowed stays swallowed.
        if type == .keyUp, swallowedKeys.remove(keyCode) != nil {
            return true
        }
        if type == .keyDown, keyCode == KeyCode.escape, case .loading = phase {
            // Esc before the switch happened: don't switch.
            swallowedKeys.insert(keyCode)
            cancel()
            return true
        }
        guard var events = heldEvents, events.count < Self.maxHeldEvents, let copy = event.copy() else {
            return false
        }
        events.append(copy)
        heldEvents = events
        return true
    }

    /// Starts holding keys, or keeps holding them for another step of the switch.
    private func startHolding() {
        if heldEvents == nil {
            heldEvents = []
        }
        holdCount += 1
        let holdCount = self.holdCount
        // Never hold the keyboard for long, whatever happens to the switch.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdTimeout) { [weak self] in
            guard let self, self.holdCount == holdCount else { return }
            self.releaseHeldEvents(to: nil)
        }
    }

    /// Replays held keys: to the app with `pid`, or to whatever app is in front when nil.
    private func releaseHeldEvents(to pid: pid_t?) {
        guard let events = heldEvents else { return }
        heldEvents = nil
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    // MARK: - Switching

    private func open(backwards: Bool) {
        generation += 1
        let generation = self.generation
        phase = .loading(backwards: backwards, moves: 0, released: false)

        let ranks = history.ranks()
        let pendingSwitch = history.pendingSwitch()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        openedFromPID = frontmostPID
        let lister = self.lister
        listingQueue.async {
            let list = lister.windowsOnCurrentDesktop(
                ranks: ranks,
                frontmostPID: frontmostPID,
                pendingSwitch: pendingSwitch
            )
            DispatchQueue.main.async { [weak self] in
                self?.listReady(list, generation: generation)
            }
        }
    }

    private func listReady(_ list: WindowList, generation: Int) {
        guard generation == self.generation, case let .loading(backwards, moves, released) = phase else { return }
        guard !list.windows.isEmpty else {
            cancel()
            return
        }

        var selection = SwitcherSelection(
            count: list.windows.count,
            openingBackwards: backwards,
            firstIsCurrent: list.firstIsCurrent
        )
        selection.move(by: moves)

        if released {
            // ⌥ was let go before the list was ready: switch without showing
            // the panel, unless you moved to another app in the meantime.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == openedFromPID else {
                cancel()
                return
            }
            phase = .idle
            switchTo(list.windows[selection.index])
        } else {
            windows = list.windows
            phase = .open(selection)
            panel.show(windows, selectedIndex: selection.index)
        }
    }

    private func move(by delta: Int) {
        switch phase {
        case .idle:
            break
        case let .loading(backwards, moves, released):
            phase = .loading(backwards: backwards, moves: moves + delta, released: released)
        case var .open(selection):
            selection.move(by: delta)
            phase = .open(selection)
            panel.select(selection.index)
        }
    }

    private func optionReleased() {
        switch phase {
        case .idle:
            break
        case let .loading(backwards, moves, released):
            guard !released else { return }
            phase = .loading(backwards: backwards, moves: moves, released: true)
            startHolding()
            let generation = self.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadingTimeout) { [weak self] in
                guard let self, self.generation == generation, case .loading = self.phase else { return }
                self.cancel()
            }
        case let .open(selection):
            let window = windows[selection.index]
            close()
            switchTo(window)
        }
    }

    private func switchTo(_ window: WindowInfo) {
        history.switched(to: window.id, pid: window.pid)
        switchCount += 1
        let switchCount = self.switchCount
        startHolding()
        activator.activate(window) { [weak self] in
            guard let self, self.switchCount == switchCount else { return }
            self.releaseHeldEvents(to: window.pid)
        }
    }

    private func close() {
        phase = .idle
        windows = []
        panel.orderOut(nil)
    }
}
