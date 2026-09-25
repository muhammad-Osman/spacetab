import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(AppSettings.Key.style)
    private var style = AppSettings.defaultStyle
    @AppStorage(AppSettings.Key.theme)
    private var theme = AppSettings.defaultTheme
    @AppStorage(AppSettings.Key.size)
    private var size = AppSettings.defaultSize
    @AppStorage(AppSettings.Key.spacing)
    private var spacing = AppSettings.defaultSpacing
    @AppStorage(AppSettings.Key.cornerRadius)
    private var cornerRadius = AppSettings.defaultCornerRadius
    @AppStorage(AppSettings.Key.opacity)
    private var opacity = AppSettings.defaultOpacity
    @AppStorage(AppSettings.Key.animation)
    private var animation = AppSettings.defaultAnimation
    @AppStorage(AppSettings.Key.minimizedWindows)
    private var minimizedWindows = AppSettings.defaultMinimizedWindows
    @AppStorage(AppSettings.Key.hiddenAppWindows)
    private var hiddenAppWindows = AppSettings.defaultHiddenAppWindows
    @AppStorage(AppSettings.Key.screens)
    private var screens = AppSettings.defaultScreens
    @AppStorage(AppSettings.Key.excludedApps)
    private var excludedApps = ""

    @State private var shortcuts = ShortcutSettings.load()
    @State private var screenRecordingGranted = ScreenRecordingPermission.isGranted
    @State private var launchStatus = LaunchAtLogin.status
    @State private var launchError: String?

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            windowsTab
                .tabItem { Label("Windows", systemImage: "macwindow.on.rectangle") }
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 440)
        // Permissions and the login item can change in System Settings or the menu bar menu.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchStatus = LaunchAtLogin.status
            refreshScreenRecording()
        }
        .onChange(of: style) { _, newValue in
            if newValue == .thumbnails {
                refreshScreenRecording()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchAtLoginChanged)) { _ in
            launchStatus = LaunchAtLogin.status
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section {
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
                        if ScreenRecordingPermission.wasRequested {
                            HStack {
                                Text("Already allowed in System Settings? macOS needs SpaceTab reopened.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reopen SpaceTab") { ScreenRecordingPermission.relaunch() }
                            }
                        }
                    }
                }
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Picker("Size", selection: $size) {
                    ForEach(SwitcherSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Spacing", selection: $spacing) {
                    ForEach(SwitcherSpacing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Slider(value: $cornerRadius, in: 0...24, step: 2) {
                    Text("Corner radius")
                }
                Slider(value: $opacity, in: 0...1) {
                    Text("Background")
                } minimumValueLabel: {
                    Text("See-through").font(.caption)
                } maximumValueLabel: {
                    Text("Solid").font(.caption)
                }
                Picker("Animation", selection: $animation) {
                    ForEach(AnimationSpeed.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Windows

    private var windowsTab: some View {
        Form {
            Section {
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
            Section("Never show these apps") {
                let ids = AppSettings.parseExcluded(excludedApps).sorted()
                if ids.isEmpty {
                    Text("No apps excluded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ids, id: \.self) { id in
                    HStack {
                        Text(Self.appName(forBundleID: id))
                        Spacer()
                        Button("Remove") { setExcluded(AppSettings.parseExcluded(excludedApps).subtracting([id])) }
                    }
                }
                Button("Add App…") { chooseApp() }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app to keep out of the switcher."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        setExcluded(AppSettings.parseExcluded(excludedApps).union([id]))
    }

    private func setExcluded(_ ids: Set<String>) {
        excludedApps = AppSettings.formatExcluded(ids)
    }

    private static func appName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), let bundle = Bundle(url: url) else {
            return id
        }
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        return displayName ?? name ?? id
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section {
                ForEach($shortcuts) { $shortcut in
                    HStack(spacing: 12) {
                        ShortcutRecorder(shortcut: $shortcut)
                            .frame(width: 130)
                        Picker("Scope", selection: $shortcut.scope) {
                            ForEach(ShortcutScope.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        Button {
                            shortcuts.removeAll { $0.id == shortcut.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .disabled(shortcuts.count == 1)
                        .help("Remove this shortcut")
                    }
                }
                if shortcuts.count < Shortcut.maxCount {
                    Button("Add Shortcut") {
                        shortcuts.append(Shortcut(keyCode: 48, modifiers: [.control, .option], scope: .currentApp))
                    }
                }
            } footer: {
                Text("Click a shortcut to change it, then press the new keys. Hold the modifier keys and press the key to open the switcher; let go to switch. Add ⇧ to go backwards. Up to \(Shortcut.maxCount) shortcuts.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: shortcuts) { _, newValue in
            ShortcutSettings.save(newValue)
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
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
            Section("Keys in the switcher") {
                keyRow("/", "Search windows, then Return to switch")
                keyRow("W", "Close window")
                keyRow("M", "Minimize window")
                keyRow("Q", "Quit app")
                keyRow("F", "Full screen")
                keyRow("H", "Hide app")
                keyRow("Esc", "Close without switching")
            }
        }
        .formStyle(.grouped)
    }

    private func refreshScreenRecording() {
        Task {
            await ScreenRecordingPermission.refresh()
            screenRecordingGranted = ScreenRecordingPermission.isGranted
        }
    }

    private func keyRow(_ key: String, _ action: String) -> some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 40, alignment: .leading)
            Text(action)
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
