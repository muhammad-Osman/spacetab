import AppKit

/// Where minimized windows, or windows of hidden apps, appear in the switcher.
enum WindowPlacement: String, CaseIterable, Identifiable, Sendable {
    case mixed
    case atEnd
    case hidden

    var id: Self { self }

    var title: String {
        switch self {
        case .mixed: "Show"
        case .atEnd: "Show at the end"
        case .hidden: "Don't show"
        }
    }
}

/// How the switcher shows windows.
enum SwitcherStyle: String, CaseIterable, Identifiable, Sendable {
    case titles
    case appIcons
    case thumbnails

    var id: Self { self }

    var title: String {
        switch self {
        case .titles: "Titles"
        case .appIcons: "App Icons"
        case .thumbnails: "Thumbnails"
        }
    }
}

/// Which screens the switcher lists windows from.
enum ScreenChoice: String, CaseIterable, Identifiable, Sendable {
    case all
    case withMouse

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All screens"
        case .withMouse: "The screen with the mouse"
        }
    }
}

enum Theme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum SwitcherSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.25
        }
    }
}

enum SwitcherSpacing: String, CaseIterable, Identifiable, Sendable {
    case compact
    case normal
    case roomy

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .normal: "Normal"
        case .roomy: "Roomy"
        }
    }

    var factor: CGFloat {
        switch self {
        case .compact: 0.5
        case .normal: 1
        case .roomy: 1.75
        }
    }
}

enum AnimationSpeed: String, CaseIterable, Identifiable, Sendable {
    case off
    case fast
    case normal

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .fast: "Fast"
        case .normal: "Normal"
        }
    }

    /// How long the switcher takes to fade in.
    var fadeDuration: TimeInterval {
        switch self {
        case .off: 0
        case .fast: 0.08
        case .normal: 0.18
        }
    }
}

/// The user's settings, stored in UserDefaults.
enum AppSettings {
    enum Key {
        static let style = "style"
        static let minimizedWindows = "minimizedWindows"
        static let hiddenAppWindows = "hiddenAppWindows"
        static let screens = "screens"
        static let excludedApps = "excludedApps"
        static let theme = "theme"
        static let size = "size"
        static let spacing = "spacing"
        static let cornerRadius = "cornerRadius"
        static let opacity = "opacity"
        static let animation = "animation"
    }

    static let defaultStyle = SwitcherStyle.titles
    static let defaultMinimizedWindows = WindowPlacement.atEnd
    static let defaultHiddenAppWindows = WindowPlacement.atEnd
    static let defaultScreens = ScreenChoice.all
    static let defaultTheme = Theme.system
    static let defaultSize = SwitcherSize.medium
    static let defaultSpacing = SwitcherSpacing.normal
    static let defaultCornerRadius = 14.0
    /// 0 is see-through (blurred), 1 is solid.
    static let defaultOpacity = 0.0
    static let defaultAnimation = AnimationSpeed.fast

    static var style: SwitcherStyle {
        read(Key.style) ?? defaultStyle
    }

    static var minimizedWindows: WindowPlacement {
        read(Key.minimizedWindows) ?? defaultMinimizedWindows
    }

    static var hiddenAppWindows: WindowPlacement {
        read(Key.hiddenAppWindows) ?? defaultHiddenAppWindows
    }

    static var screens: ScreenChoice {
        read(Key.screens) ?? defaultScreens
    }

    /// Bundle IDs of apps whose windows never appear in the switcher.
    /// Stored as one line per app, so SwiftUI's @AppStorage can edit it.
    static var excludedBundleIDs: Set<String> {
        parseExcluded(UserDefaults.standard.string(forKey: Key.excludedApps) ?? "")
    }

    static func parseExcluded(_ stored: String) -> Set<String> {
        Set(stored.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    static func formatExcluded(_ ids: some Sequence<String>) -> String {
        ids.sorted().joined(separator: "\n")
    }

    static var appearance: SwitcherAppearance {
        let defaults = UserDefaults.standard
        return SwitcherAppearance(
            theme: read(Key.theme) ?? defaultTheme,
            scale: (read(Key.size) ?? defaultSize).scale,
            spacingFactor: (read(Key.spacing) ?? defaultSpacing).factor,
            cornerRadius: defaults.object(forKey: Key.cornerRadius) as? Double ?? defaultCornerRadius,
            opacity: defaults.object(forKey: Key.opacity) as? Double ?? defaultOpacity,
            fadeDuration: (read(Key.animation) ?? defaultAnimation).fadeDuration
        )
    }

    private static func read<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:))
    }
}

/// How the switcher looks, captured when it opens.
struct SwitcherAppearance: Sendable {
    var theme = AppSettings.defaultTheme
    var scale: CGFloat = 1
    var spacingFactor: CGFloat = 1
    var cornerRadius: CGFloat = AppSettings.defaultCornerRadius
    var opacity: CGFloat = AppSettings.defaultOpacity
    var fadeDuration: TimeInterval = 0
}

/// What to list, captured on the main thread when the switcher opens.
struct ListingOptions: Sendable {
    var minimizedWindows: WindowPlacement
    var hiddenAppWindows: WindowPlacement
    var excludedBundleIDs: Set<String> = []
    /// Screen frames in CoreGraphics coordinates (origin at the top left of
    /// the main display).
    var screens: [CGRect] = []
    /// Only windows on this screen, an index into `screens`. Nil for all screens.
    var onlyScreen: Int?
    /// Also windows on other desktops.
    var allDesktops = false
    /// Only windows of this app.
    var onlyPID: pid_t?

    /// Whether a window with these bounds is on the chosen screen.
    func includes(_ bounds: CGRect) -> Bool {
        guard let onlyScreen else { return true }
        return Self.screenIndex(of: bounds, screens: screens) == onlyScreen
    }

    /// The screen a window is on: the one showing most of it, or the nearest
    /// one when it is on none.
    static func screenIndex(of bounds: CGRect, screens: [CGRect]) -> Int? {
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        let overlaps = screens.map { area($0.intersection(bounds)) }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
            return best
        }
        func distance(_ screen: CGRect) -> CGFloat {
            hypot(screen.midX - bounds.midX, screen.midY - bounds.midY)
        }
        return screens.indices.min { distance(screens[$0]) < distance(screens[$1]) }
    }

    @MainActor
    static func current(scope: ShortcutScope, frontmostPID: pid_t?) -> ListingOptions {
        let appKitScreens = NSScreen.screens
        let primaryHeight = appKitScreens.first?.frame.maxY ?? 0
        // AppKit puts the origin at the bottom left; CoreGraphics at the top left.
        let screens = appKitScreens.map { screen in
            let frame = screen.frame
            return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        let mouseScreen = appKitScreens.firstIndex { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        return ListingOptions(
            minimizedWindows: AppSettings.minimizedWindows,
            hiddenAppWindows: AppSettings.hiddenAppWindows,
            excludedBundleIDs: AppSettings.excludedBundleIDs,
            screens: screens,
            onlyScreen: AppSettings.screens == .withMouse ? mouseScreen : nil,
            allDesktops: scope != .currentDesktop,
            onlyPID: scope == .currentApp ? frontmostPID : nil
        )
    }
}
