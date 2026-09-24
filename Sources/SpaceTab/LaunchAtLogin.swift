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

    /// Already registered counts as success.
    static func enable() throws {
        do {
            try SMAppService.mainApp.register()
        } catch let error as NSError where error.code == kSMErrorAlreadyRegistered {
        }
    }

    /// Already removed (for example in System Settings) counts as success.
    static func disable() throws {
        do {
            try SMAppService.mainApp.unregister()
        } catch let error as NSError where error.code == kSMErrorJobNotFound {
        }
    }

    /// Opens System Settings > General > Login Items, where the user approves SpaceTab.
    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
