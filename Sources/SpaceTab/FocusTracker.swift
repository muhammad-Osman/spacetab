import AppKit
@preconcurrency import ApplicationServices

/// Keeps `WindowHistory` up to date: a window moves to the front of the
/// history whenever it gets keyboard focus, whether by a click, ⌘ Tab, ⌘ `
/// or SpaceTab itself.
///
/// Watches app activations, and each app's focused window through an
/// `AXObserver`. Accessibility calls run on background queues, so a busy app
/// never holds up the main thread.
@MainActor
final class FocusTracker {
    private static let maxAttempts = 5
    private static let focusReadAttempts = 3

    private let history: WindowHistory
    private let readQueue = DispatchQueue(label: "SpaceTab.FocusTracker.read", qos: .utility)
    private let registerQueue = DispatchQueue(label: "SpaceTab.FocusTracker.register", qos: .utility)
    private var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    private var pending = Set<pid_t>()
    /// Apps that can't send focus notifications. Not retried.
    private var unsupported = Set<pid_t>()
    private var activationToken: NSObjectProtocol?
    private var runningAppsObservation: NSKeyValueObservation?

    init(history: WindowHistory) {
        self.history = history
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.recordFocusedWindow(of: pid)
                // Retries apps that were too busy to observe earlier.
                self?.observe(pid)
            }
        }
        // Unlike the launch notification, this also covers apps without a Dock icon.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            let added = (change.newValue ?? []).map(\.processIdentifier)
            let removed = (change.oldValue ?? []).map(\.processIdentifier)
            DispatchQueue.main.async {
                removed.forEach { self?.stopObserving($0) }
                added.forEach { self?.observe($0) }
            }
        }

        for app in NSWorkspace.shared.runningApplications {
            observe(app.processIdentifier)
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            recordFocusedWindow(of: frontmost.processIdentifier)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(activationToken)
        }
        activationToken = nil
        runningAppsObservation?.invalidate()
        runningAppsObservation = nil
        for pid in Array(observers.keys) {
            stopObserving(pid)
        }
        pending = []
    }

    fileprivate func windowFocused(_ element: AXUIElement) {
        readQueue.async {
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, let id = AX.windowID(of: element) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.record(id, pid: pid)
            }
        }
    }

    private func record(_ id: CGWindowID, pid: pid_t) {
        guard isRunning else { return }
        if !history.focused(id, pid: pid) {
            // Ignored while a switch settles. Read again afterwards, so a
            // switch that really ended on another window is still recorded.
            DispatchQueue.main.asyncAfter(deadline: .now() + WindowHistory.settleTime) { [weak self] in
                self?.recordFocusedWindow(of: pid)
            }
        }
    }

    /// Reads the app's focused window. An app that is busy right after
    /// activating is asked again, and as a last resort its top window on
    /// screen is taken.
    private func recordFocusedWindow(of pid: pid_t, attempt: Int = 1) {
        readQueue.async {
            let id = AX.focusedWindowID(of: pid)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                if let id {
                    self.record(id, pid: pid)
                    return
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                if attempt < Self.focusReadAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.recordFocusedWindow(of: pid, attempt: attempt + 1)
                    }
                } else if let top = WindowLister.topWindowID(of: pid) {
                    self.record(top, pid: pid)
                }
            }
        }
    }

    private func observe(_ pid: pid_t, attempt: Int = 1) {
        guard
            isRunning,
            pid != getpid(),
            observers[pid] == nil,
            !unsupported.contains(pid),
            attempt > 1 || !pending.contains(pid),
            let app = NSRunningApplication(processIdentifier: pid),
            !app.isTerminated,
            app.activationPolicy != .prohibited
        else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, focusChangedCallback, &created) == .success, let observer = created else { return }
        pending.insert(pid)

        registerQueue.async { [self] in
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let result = AXObserverAddNotification(
                observer,
                AXUIElementCreateApplication(pid),
                kAXFocusedWindowChangedNotification as CFString,
                refcon
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pending.contains(pid) else { return }
                switch result {
                case .success:
                    self.pending.remove(pid)
                    self.observers[pid] = observer
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                case .notificationUnsupported, .notImplemented:
                    self.pending.remove(pid)
                    self.unsupported.insert(pid)
                default:
                    guard attempt < Self.maxAttempts else {
                        // Tried again the next time the app is activated.
                        self.pending.remove(pid)
                        return
                    }
                    // A freshly launched or busy app isn't ready yet. Try again shortly.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.observe(pid, attempt: attempt + 1)
                    }
                }
            }
        }
    }

    private func stopObserving(_ pid: pid_t) {
        pending.remove(pid)
        unsupported.remove(pid)
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}

private func focusChangedCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
    // Observer run loop sources are on the main run loop.
    MainActor.assumeIsolated { tracker.windowFocused(element) }
}
