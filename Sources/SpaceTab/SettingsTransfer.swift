import AppKit

/// Saves the settings to a file and loads them back, to move them to another Mac.
enum SettingsTransfer {
    enum TransferError: LocalizedError {
        case notASettingsFile

        var errorDescription: String? {
            String(localized: "This file doesn't contain SpaceTab settings.")
        }
    }

    private static let formatKey = "spacetab"
    private static let formatVersion = 1
    private static let keys = [
        AppSettings.Key.style, AppSettings.Key.theme, AppSettings.Key.size, AppSettings.Key.spacing,
        AppSettings.Key.cornerRadius, AppSettings.Key.opacity, AppSettings.Key.animation,
        AppSettings.Key.minimizedWindows, AppSettings.Key.hiddenAppWindows, AppSettings.Key.screens,
        AppSettings.Key.excludedApps, AppSettings.Key.groupByApp, AppSettings.Key.showMenuBarIcon,
    ]

    /// Every setting the user has changed, plus the shortcuts, as JSON.
    static func export(from defaults: UserDefaults = .standard) throws -> Data {
        var settings: [String: Any] = [formatKey: formatVersion]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                settings[key] = value
            }
        }
        let shortcuts = try JSONEncoder().encode(ShortcutSettings.load(from: defaults))
        settings[ShortcutSettings.key] = try JSONSerialization.jsonObject(with: shortcuts)
        return try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }

    /// Replaces the settings with the ones in `data`. Unknown keys are ignored.
    @MainActor
    static func `import`(_ data: Data, into defaults: UserDefaults = .standard) throws {
        guard
            let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            settings[formatKey] is Int
        else { throw TransferError.notASettingsFile }

        for key in keys {
            if let value = settings[key], value is String || value is Bool || value is NSNumber {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        if let shortcutsJSON = settings[ShortcutSettings.key] {
            let shortcutsData = try JSONSerialization.data(withJSONObject: shortcutsJSON)
            let shortcuts = try JSONDecoder().decode([Shortcut].self, from: shortcutsData)
            ShortcutSettings.save(shortcuts.isEmpty ? Shortcut.defaults : shortcuts, to: defaults)
        } else {
            ShortcutSettings.save(Shortcut.defaults, to: defaults)
        }
        NotificationCenter.default.post(name: .settingsImported, object: nil)
    }

    /// Asks where to save, then exports.
    @MainActor
    static func exportWithPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SpaceTab Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try export().write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Asks for a file, then imports it.
    @MainActor
    static func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Choose a SpaceTab settings file.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try `import`(Data(contentsOf: url))
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

extension Notification.Name {
    /// Posted after settings were imported, so views showing them refresh.
    static let settingsImported = Notification.Name("SpaceTabSettingsImported")
}
