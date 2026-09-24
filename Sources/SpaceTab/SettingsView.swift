import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.style)
    private var style = AppSettings.defaultStyle
    @AppStorage(AppSettings.Key.minimizedWindows)
    private var minimizedWindows = AppSettings.defaultMinimizedWindows
    @AppStorage(AppSettings.Key.hiddenAppWindows)
    private var hiddenAppWindows = AppSettings.defaultHiddenAppWindows
    @AppStorage(AppSettings.Key.screens)
    private var screens = AppSettings.defaultScreens

    @State private var screenRecordingGranted = ScreenRecordingPermission.isGranted
    @State private var launchStatus = LaunchAtLogin.status
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Style", selection: $style) {
                    ForEach(SwitcherStyle.allCases) { Text($0.title).tag($0) }
                }
                if style == .thumbnails, !screenRecordingGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Thumbnails need Screen Recording permission. Until then, app icons are shown.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Allow…") { ScreenRecordingPermission.request() }
                        }
                        Text("macOS may ask you to reopen SpaceTab after you allow it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Windows") {
                Picker("Minimized windows", selection: $minimizedWindows) {
                    ForEach(WindowPlacement.allCases) { Text($0.title).tag($0) }
                }
                Picker("Windows of hidden apps", selection: $hiddenAppWindows) {
                    ForEach(WindowPlacement.allCases) { Text($0.title).tag($0) }
                }
                Picker("Show windows from", selection: $screens) {
                    ForEach(ScreenChoice.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin)
                if launchStatus == .requiresApproval {
                    HStack {
                        Text("Allow SpaceTab in Login Items to finish.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LaunchAtLogin.openSettings() }
                    }
                }
                if let launchError {
                    Text(launchError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        // Permissions and the login item can change in System Settings or the menu bar menu.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchStatus = LaunchAtLogin.status
            screenRecordingGranted = ScreenRecordingPermission.isGranted
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchAtLoginChanged)) { _ in
            launchStatus = LaunchAtLogin.status
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { launchStatus == .enabled },
            set: { enabled in
                do {
                    if enabled {
                        try LaunchAtLogin.enable()
                    } else {
                        try LaunchAtLogin.disable()
                    }
                    launchError = nil
                } catch {
                    launchError = error.localizedDescription
                }
                launchStatus = LaunchAtLogin.status
                NotificationCenter.default.post(name: .launchAtLoginChanged, object: nil)
            }
        )
    }
}
