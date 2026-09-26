import AppKit

private enum KeyCode {
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let delete: Int64 = 51
    static let `return`: Int64 = 36
    static let enter: Int64 = 76
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
        /// Typing filters the list. The switcher stays open without ⌥, and
        /// Return switches.
        case searching(query: String, selection: SwitcherSelection)
    }

    /// How long to wait for the window list after ⌥ was released before giving up.
    private static let loadingTimeout: TimeInterval = 0.5

    private let history: WindowHistory
    private let panel = SwitcherPanel()
    private let lister = WindowLister()
    private let activator = WindowActivator()
    private let keyHold = KeyHold()
    private let listingQueue = DispatchQueue(label: "SpaceTab.listing", qos: .userInteractive)
    private let actionQueue = DispatchQueue(label: "SpaceTab.actions", qos: .userInteractive)

    private var phase = Phase.idle
    private var shortcuts = ShortcutSettings.load()
    private var shortcutsToken: NSObjectProtocol?
    /// The shortcut that opened the switcher. Letting go of its modifiers switches.
    private var activeShortcut: Shortcut?
    /// All listed windows, and the ones matching the search.
    private var windows: [WindowInfo] = []
    private var matching: [WindowInfo] = []
    private var options = ListingOptions(minimizedWindows: .atEnd, hiddenAppWindows: .atEnd)
    private var appearance = SwitcherAppearance()
    /// The screen the switcher opens on: the one with the mouse when ⌥ Tab was pressed.
    private var screen: NSScreen?
    /// Bumped on every open and cancel, so a window list that arrives late is ignored.
    private var generation = 0
    /// The app in front when the switcher opened, and the app of a switch
    /// still on its way then. Either may be in front when the list arrives.
    private var openedFromPIDs = Set<pid_t>()
    /// Keys whose key-down was swallowed. Their key-up is swallowed too, and
    /// only theirs, so no app sees a release without a press or misses one.
    private var swallowedKeys = Set<Int64>()
    /// Bumped for each switch and each new open or cancel, so only the latest
    /// switch releases held keys.
    private var switchCount = 0
    /// While searching, clicking elsewhere or switching apps ends the search.
    private var searchActivationToken: NSObjectProtocol?
    private var searchClickMonitor: Any?

    init(history: WindowHistory) {
        self.history = history
        shortcutsToken = NotificationCenter.default.addObserver(
            forName: ShortcutSettings.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shortcuts = ShortcutSettings.load() }
        }
        panel.onHover = { [weak self] index in
            self?.select(index)
        }
        panel.onClick = { [weak self] index in
            self?.select(index)
            self?.commit()
        }
        keyHold.onSystemShortcut = { [weak self] in
            // Whatever the shortcut opened is what you use now; stop
            // re-focusing the window you switched to.
            guard let self else { return }
            self.switchCount += 1
            self.activator.cancelChecks()
        }
    }

    /// Whether key presses go to the switcher instead of the app in front.
    private var isCapturingKeys: Bool {
        switch phase {
        case .idle: false
        case .loading(_, _, let released): !released
        case .open, .searching: true
        }
    }

    private var isSearching: Bool {
        if case .searching = phase { return true }
        return false
    }

    /// Handles one keyboard event. Returns `true` to swallow it.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == KeyHold.replayTag {
            return false
        }
        if ShortcutSettings.isRecording, NSApp.isActive {
            // The Settings window is waiting for a key; let it have every key.
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch type {
        case .flagsChanged:
            if let activeShortcut, !activeShortcut.isHeld(in: flags) {
                modifiersReleased()
            }
            return false

        case .keyDown, .keyUp:
            if keyHold.isHolding {
                let isKeyDown = type == .keyDown
                if isKeyDown, shortcut(matching: keyCode, flags: flags) != nil {
                    // A new switch: the keys held so far belong to the app in front.
                    keyHold.release(to: nil)
                } else if isKeyDown, keyCode == KeyCode.escape, case .loading = phase {
                    // Esc before the switch happened: don't switch.
                    swallowedKeys.insert(keyCode)
                    cancel()
                    return true
                } else {
                    return keyHold.hold(event, type: type, keyCode: keyCode, swallowedKeys: &swallowedKeys)
                }
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
        switchCount += 1
        close()
        keyHold.release(to: nil)
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
        // Keys typed while the tap was off already went through; send the held ones too.
        keyHold.release(to: nil)
        if isCapturingKeys, !isSearching, let activeShortcut,
           !activeShortcut.isHeld(in: CGEventSource.flagsState(.combinedSessionState)) {
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
        if isCapturingKeys, !isSearching, let activeShortcut, !activeShortcut.isHeld(in: flags) {
            // The modifier release was missed, for example while macOS had the
            // tap turned off. Give the keyboard back instead of eating keys.
            cancel()
        }
        if isRepeat, !swallowedKeys.contains(keyCode) {
            // A key held down in an app keeps going to that app, even if ⌥ is added.
            return false
        }
        if let shortcut = shortcut(matching: keyCode, flags: flags) {
            swallowedKeys.insert(keyCode)
            let backwards = flags.contains(.maskShift)
            if isCapturingKeys {
                // While open, only the shortcut that opened the switcher moves.
                if shortcut.id == activeShortcut?.id {
                    move(by: backwards ? -1 : 1)
                }
            } else {
                open(shortcut, backwards: backwards)
            }
            return true
        }
        guard isCapturingKeys else {
            // Repeats of a key held since the switcher closed.
            return isRepeat
        }
        swallowedKeys.insert(keyCode)

        switch phase {
        case .idle:
            break
        case .loading:
            handleNavigationKey(keyCode)
        case .open:
            if handleNavigationKey(keyCode) { break }
            // Keys with a modifier beyond the shortcut's own are something else.
            guard extraModifiers(in: flags, keyCode: keyCode).isEmpty else { break }
            let characters = Self.characters(keyCode: keyCode, shift: flags.contains(.maskShift))
            if characters.contains("/") {
                startSearch()
            } else if let action = characters.lazy.compactMap({ WindowAction(character: $0) }).first {
                perform(action)
            }
        case .searching(let query, _):
            return handleSearchKey(keyCode, flags: flags, query: query)
        }
        return true
    }

    /// The modifiers held beyond the ones the active shortcut needs.
    private func extraModifiers(in flags: CGEventFlags, keyCode: Int64) -> Shortcut.Modifiers {
        Shortcut.Modifiers(flags: flags, keyCode: keyCode).subtracting(activeShortcut?.modifiers ?? [])
    }

    /// What the key types on the current layout and, on a non-Latin layout,
    /// on the Latin one too, so W still closes a window on a Cyrillic keyboard.
    private static func characters(keyCode: Int64, shift: Bool) -> [String] {
        [KeyTranslator.character(keyCode: keyCode, shift: shift), KeyTranslator.asciiCharacter(keyCode: keyCode, shift: shift)]
            .compactMap { $0 }
    }

    /// Arrow keys and Esc, which work the same whenever the switcher is open.
    @discardableResult
    private func handleNavigationKey(_ keyCode: Int64) -> Bool {
        switch keyCode {
        case KeyCode.left: move(by: -1)
        case KeyCode.right: move(by: 1)
        case KeyCode.up: moveRow(by: -1)
        case KeyCode.down: moveRow(by: 1)
        case KeyCode.escape: cancel()
        default: return false
        }
        return true
    }

    /// Up and down go to the cell above or below in the grid styles. In a
    /// list, that is the previous or next window.
    private func moveRow(by delta: Int) {
        switch phase {
        case .idle:
            break
        case .loading:
            move(by: delta)
        case .open, .searching:
            let target = panel.index(from: currentIndex, rowDelta: delta)
            move(by: target - currentIndex)
        }
    }

    /// Returns `true` to swallow the key.
    private func handleSearchKey(_ keyCode: Int64, flags: CGEventFlags, query: String) -> Bool {
        let extra = extraModifiers(in: flags, keyCode: keyCode)
        if extra.contains(.command) || extra.contains(.control) {
            // A shortcut for something else, such as ⌘ Tab or ⌘ Space: leave
            // the search and let it through.
            swallowedKeys.remove(keyCode)
            cancel()
            return false
        }
        switch keyCode {
        case KeyCode.tab:
            move(by: flags.contains(.maskShift) ? -1 : 1)
        case KeyCode.return, KeyCode.enter:
            commit()
        case KeyCode.delete:
            setQuery(String(query.dropLast()))
        default:
            if handleNavigationKey(keyCode) { break }
            if let character = KeyTranslator.character(keyCode: keyCode, shift: flags.contains(.maskShift)) {
                setQuery(query + character)
            }
        }
        return true
    }

    private func handleKeyUp(keyCode: Int64, flags: CGEventFlags) -> Bool {
        if swallowedKeys.remove(keyCode) != nil {
            return true
        }
        if isCapturingKeys, !isSearching, let activeShortcut, !activeShortcut.isHeld(in: flags) {
            cancel()
        }
        return false
    }

    private func shortcut(matching keyCode: Int64, flags: CGEventFlags) -> Shortcut? {
        shortcuts.first { $0.matches(keyCode: keyCode, flags: flags) }
    }

    // MARK: - Search and actions

    private func startSearch() {
        guard case .open = phase else { return }
        matching = windows
        phase = .searching(query: "", selection: SwitcherSelection(count: matching.count, index: 0))
        showPanel()
        // Without a modifier held, nothing else ends the search: watch for
        // the user moving on to another app or clicking outside the switcher.
        searchActivationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.isSearching == true { self?.cancel() }
            }
        }
        // Clicks on the switcher itself don't reach a global monitor.
        searchClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.isSearching == true { self?.cancel() }
            }
        }
    }

    private func stopWatchingSearch() {
        if let searchActivationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(searchActivationToken)
        }
        searchActivationToken = nil
        if let searchClickMonitor {
            NSEvent.removeMonitor(searchClickMonitor)
        }
        searchClickMonitor = nil
    }

    private func setQuery(_ query: String) {
        guard case .searching = phase else { return }
        matching = WindowSearch.filter(windows, query: query)
        phase = .searching(query: query, selection: SwitcherSelection(count: matching.count, index: 0))
        showPanel()
    }

    /// Runs the action on the selected window. Once the app has taken it,
    /// the list is updated to match without asking every app again.
    private func perform(_ action: WindowAction) {
        guard let window = selectedWindow else { return }
        let restoring = switch action {
        case .minimize: window.state == .minimized
        case .hideApp: NSRunningApplication(processIdentifier: window.pid)?.isHidden == true
        default: false
        }
        let generation = self.generation
        actionQueue.async {
            let taken = action.perform(on: window, restoring: restoring)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                guard taken else {
                    NSSound.beep()
                    return
                }
                self.apply(action, to: window, restoring: restoring)
            }
        }
    }

    private func apply(_ action: WindowAction, to window: WindowInfo, restoring: Bool) {
        func placement(_ state: WindowInfo.State) -> WindowPlacement {
            state == .minimized ? options.minimizedWindows : options.hiddenAppWindows
        }
        switch action {
        case .close:
            windows.removeAll { $0.id == window.id }
        case .quitApp:
            windows.removeAll { $0.pid == window.pid }
        case .minimize:
            toggleState(.minimized, restoring: restoring, placement: placement(.minimized)) { $0.id == window.id }
        case .hideApp:
            toggleState(.appHidden, restoring: restoring, placement: placement(.appHidden)) { $0.pid == window.pid }
        case .fullScreen:
            return
        }
        if case .searching(let query, _) = phase {
            matching = WindowSearch.filter(windows, query: query)
        }
        guard !listedWindows.isEmpty else {
            cancel()
            return
        }
        let index = currentIndex
        switch phase {
        case .open:
            phase = .open(SwitcherSelection(count: listedWindows.count, index: index))
        case .searching(let query, _):
            phase = .searching(query: query, selection: SwitcherSelection(count: matching.count, index: index))
        default:
            return
        }
        showPanel()
    }

    /// Windows matching `matches` become `state`, or normal again when
    /// `restoring`. Minimized windows stay minimized when their app is hidden or shown.
    private func toggleState(
        _ state: WindowInfo.State,
        restoring: Bool,
        placement: WindowPlacement,
        matches: @escaping (WindowInfo) -> Bool
    ) {
        let affected: (WindowInfo) -> Bool = { window in
            matches(window) && (state == .minimized || window.state != .minimized)
        }
        if !restoring, placement == .hidden {
            windows.removeAll(where: affected)
            return
        }
        var moved: [WindowInfo] = []
        windows = windows.compactMap { window in
            guard affected(window) else { return window }
            var window = window
            window.state = restoring ? .normal : state
            if !restoring, placement == .atEnd {
                moved.append(window)
                return nil
            }
            return window
        }
        windows += moved
    }

    private var listedWindows: [WindowInfo] {
        isSearching ? matching : windows
    }

    private var currentIndex: Int {
        switch phase {
        case .open(let selection), .searching(_, let selection): selection.index
        default: 0
        }
    }

    private var selectedWindow: WindowInfo? {
        let listed = listedWindows
        return listed.indices.contains(currentIndex) ? listed[currentIndex] : nil
    }

    private func showPanel() {
        let search: String? = if case .searching(let query, _) = phase { query } else { nil }
        panel.show(
            listedWindows,
            selectedIndex: currentIndex,
            style: AppSettings.style,
            search: search,
            appearance: appearance,
            on: screen
        )
    }

    // MARK: - Switching

    private func open(_ shortcut: Shortcut, backwards: Bool) {
        generation += 1
        // An earlier switch still on its way must not release keys held for this one.
        switchCount += 1
        let generation = self.generation
        activeShortcut = shortcut
        phase = .loading(backwards: backwards, moves: 0, released: false)

        let ranks = history.ranks()
        let pendingSwitch = history.pendingSwitch()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        options = ListingOptions.current(scope: shortcut.scope, frontmostPID: frontmostPID)
        appearance = AppSettings.appearance
        screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let options = self.options
        openedFromPIDs = Set([frontmostPID, pendingSwitch?.pid].compactMap { $0 })
        let lister = self.lister
        listingQueue.async {
            let list = lister.windowsOnCurrentDesktop(
                ranks: ranks,
                frontmostPID: frontmostPID,
                pendingSwitch: pendingSwitch,
                options: options
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
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard let frontmostPID, openedFromPIDs.contains(frontmostPID) else {
                cancel()
                return
            }
            phase = .idle
            switchTo(list.windows[selection.index])
        } else {
            windows = list.windows
            phase = .open(selection)
            showPanel()
        }
    }

    /// Selects the window at `index` in the shown list.
    private func select(_ index: Int) {
        switch phase {
        case .open(let selection):
            guard selection.index != index, listedWindows.indices.contains(index) else { return }
            phase = .open(SwitcherSelection(count: selection.count, index: index))
            panel.select(index)
        case .searching(let query, let selection):
            guard selection.index != index, listedWindows.indices.contains(index) else { return }
            phase = .searching(query: query, selection: SwitcherSelection(count: selection.count, index: index))
            panel.select(index)
        case .idle, .loading:
            break
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
        case .searching(let query, var selection):
            selection.move(by: delta)
            phase = .searching(query: query, selection: selection)
            panel.select(selection.index)
        }
    }

    private func modifiersReleased() {
        switch phase {
        case .idle, .searching:
            break
        case let .loading(backwards, moves, released):
            guard !released else { return }
            phase = .loading(backwards: backwards, moves: moves, released: true)
            keyHold.start()
            let generation = self.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadingTimeout) { [weak self] in
                guard let self, self.generation == generation, case .loading = self.phase else { return }
                self.cancel()
            }
        case .open:
            commit()
        }
    }

    /// Switches to the selected window and closes the switcher.
    private func commit() {
        guard let window = selectedWindow else {
            cancel()
            return
        }
        close()
        switchTo(window)
    }

    private func switchTo(_ window: WindowInfo) {
        history.switched(to: window.id, pid: window.pid)
        switchCount += 1
        let switchCount = self.switchCount
        keyHold.start(target: window.pid)
        activator.activate(window) { [weak self] reachedWindow in
            guard let self, self.switchCount == switchCount else { return }
            if reachedWindow {
                self.keyHold.release(to: window.pid)
            } else {
                // The app hasn't come forward yet (it was busy, or macOS is
                // still activating it). Keep the keys until it does.
                self.keyHold.releaseWhenActivated(window.pid)
            }
        }
    }

    private func close() {
        stopWatchingSearch()
        phase = .idle
        activeShortcut = nil
        windows = []
        matching = []
        panel.orderOut(nil)
    }
}
