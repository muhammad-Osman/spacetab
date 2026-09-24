import ServiceManagement

/// Registers SpaceTab as a login item. Only works when running from the app bundle.
enum LaunchAtLogin {
    /// Read fresh each time: the user can change it in System Settings at any moment.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }

    /// Opens System Settings > General > Login Items, where the user approves SpaceTab.
    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
