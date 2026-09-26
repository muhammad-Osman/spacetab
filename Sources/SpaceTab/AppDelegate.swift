import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let history = WindowHistory()
    private lazy var switcher = SwitcherController(history: history)
    private lazy var focusTracker = FocusTracker(history: history)
    private let settingsWindow = SettingsWindowController()
    private let updater = Updater.shared
    private var hotKeys: HotKeyMonitor!
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var trustTimer: Timer?
    private var failedTrustChecks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Every Accessibility call gives up after this many seconds, so a hung
        // app can only slow SpaceTab down, not freeze it.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)

        hotKeys = HotKeyMonitor { [switcher] type, event in
            switcher.handle(type, event)
        }
        hotKeys.onTapReenabled = { [switcher] in
            switcher.tapReenabled()
        }
        hotKeys.onPermissionLost = { [weak self] in
            self?.permissionLost()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "SpaceTab"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = AppSettings.showMenuBarIcon
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem.isVisible = AppSettings.showMenuBarIcon }
        }
        // Not shown, since SpaceTab has no menu bar of its own, but gives the
        // Settings window ⌘W.
        NSApp.mainMenu = Self.makeMainMenu()

        // Talk to ScreenCaptureKit now and after waking, so any permission
        // reminder from macOS shows up at a calm moment, not during ⌥ Tab.
        checkScreenRecording()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkScreenRecording() }
        }

        // Shows the macOS permission dialog when the permission is missing.
        _ = AccessibilityPermission.isGranted(prompt: true)
        if !startIfPermitted() {
            waitForPermission()
        }
    }

    /// Opening SpaceTab while it runs shows Settings. That is the way in when
    /// the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    // MARK: - Permission

    private func checkScreenRecording() {
        guard AppSettings.style == .thumbnails else { return }
        Task {
            await ScreenRecordingPermission.refresh()
            await ScreenRecordingPermission.warmUp()
        }
    }

    private func startIfPermitted() -> Bool {
        guard AccessibilityPermission.isGranted(prompt: false), hotKeys.start() else { return false }
        switcher.reset()
        // Windows on screen now are more recent than anything remembered from
        // before a permission outage.
        history.promote(WindowLister.onScreenWindowIDs())
        focusTracker.start()
        watchForRevokedPermission()
        return true
    }

    /// The user grants the permission in System Settings; poll until they do.
    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.startIfPermitted() else { return }
                timer.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    /// Revoking the permission doesn't always turn the tap off, so check for it.
    private func watchForRevokedPermission() {
        failedTrustChecks = 0
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if AccessibilityPermission.isGranted(prompt: false) {
                    self.failedTrustChecks = 0
                } else {
                    // One failed check can be a false alarm right after waking from sleep.
                    self.failedTrustChecks += 1
                    if self.failedTrustChecks >= 2 {
                        self.permissionLost()
                    }
                }
            }
        }
    }

    private func permissionLost() {
        guard hotKeys.isRunning else { return }
        trustTimer?.invalidate()
        trustTimer = nil
        switcher.reset()
        hotKeys.stop()
        focusTracker.stop()
        waitForPermission()
    }

    // MARK: - Menu

    /// Builds the menu each time it opens, so it always shows the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        menu.addItem(disabledItem(version.map { "SpaceTab \($0)" } ?? "SpaceTab"))

        if !hotKeys.isRunning {
            menu.addItem(disabledItem("Accessibility permission needed"))
            menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
        } else if IsSecureEventInputEnabled() {
            // Secure input hides key presses from event taps.
            menu.addItem(disabledItem("⌥ Tab is paused: an app is using secure input"))
        } else {
            menu.addItem(disabledItem("Press ⌥ Tab to switch windows"))
        }

        menu.addItem(.separator())
        if updater.isAvailable {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        let launchItem = item("Launch at Login", #selector(toggleLaunchAtLogin))
        switch LaunchAtLogin.status {
        case .enabled:
            launchItem.state = .on
        case .requiresApproval:
            launchItem.title = "Launch at Login (allow in System Settings)"
            launchItem.state = .mixed
        default:
            launchItem.state = .off
        }
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(item("Quit SpaceTab", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Only ⌘W. ⌘Q is left out on purpose: pressed while SpaceTab happens to
    /// be the active app, it would quit the switcher instead of the app you meant.
    private static func makeMainMenu() -> NSMenu {
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem())
        mainMenu.addItem(fileItem)
        return mainMenu
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch LaunchAtLogin.status {
            case .enabled:
                try LaunchAtLogin.disable()
            case .requiresApproval:
                LaunchAtLogin.openSettings()
            default:
                try LaunchAtLogin.enable()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change Launch at Login"
            NSApp.activate()
            alert.runModal()
            if !settingsWindow.isVisible {
                NSApp.hide(nil)
            }
        }
        NotificationCenter.default.post(name: .launchAtLoginChanged, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
