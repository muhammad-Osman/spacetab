import Foundation
import ServiceManagement

extension Notification.Name {
    /// Posted when SpaceTab changes its login item, so every place showing it updates.
    static let launchAtLoginChanged = Notification.Name("SpaceTabLaunchAtLoginChanged")
}

/// Registers SpaceTab as a login item. Only works when running from the app bundle.
enum LaunchAtLogin {
    /// Read fresh each time: the user can change it in System Settings at any moment.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Succeeds when SpaceTab ends up registered, even if macOS reports an
    /// error because it already was.
    static func enable() throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            guard [.enabled, .requiresApproval].contains(status) else { throw error }
        }
    }

    /// Succeeds when SpaceTab ends up unregistered, even if macOS reports an
    /// error because it already was removed (for example in System Settings).
    static func disable() throws {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            guard [.notRegistered, .notFound].contains(status) else { throw error }
        }
    }

    /// Opens System Settings > General > Login Items, where the user approves SpaceTab.
    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
