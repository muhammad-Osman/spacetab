import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let switcher = SwitcherController()
    private var hotKeys: HotKeyMonitor!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stop a hung app from freezing the switcher: every Accessibility call
        // gives up after this many seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)

        hotKeys = HotKeyMonitor { [switcher] type, event in
            switcher.handle(type, event)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "SpaceTab"
        )
        rebuildMenu()

        startWhenPermitted()
    }

    // MARK: - Permission

    private func startWhenPermitted() {
        if AccessibilityPermission.isGranted(prompt: true), hotKeys.start() {
            rebuildMenu()
            return
        }
        // The user grants the permission in System Settings; poll until they do.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AccessibilityPermission.isGranted(prompt: false), self.hotKeys.start() else { return }
                timer.invalidate()
                self.permissionTimer = nil
                self.rebuildMenu()
            }
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        menu.addItem(disabledItem(version.map { "SpaceTab \($0)" } ?? "SpaceTab"))

        if hotKeys.isRunning {
            menu.addItem(disabledItem("Press ⌥ Tab to switch windows"))
        } else {
            menu.addItem(disabledItem("Accessibility permission needed"))
            menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
        }

        menu.addItem(.separator())
        let launchItem = item("Launch at Login", #selector(toggleLaunchAtLogin))
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(item("Quit SpaceTab", #selector(quit), key: "q"))

        statusItem.menu = menu
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

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change Launch at Login"
            NSApp.activate()
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
