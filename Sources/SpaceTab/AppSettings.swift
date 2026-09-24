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

/// The user's settings, stored in UserDefaults.
enum AppSettings {
    enum Key {
        static let style = "style"
        static let minimizedWindows = "minimizedWindows"
        static let hiddenAppWindows = "hiddenAppWindows"
        static let screens = "screens"
    }

    static let defaultStyle = SwitcherStyle.titles
    static let defaultMinimizedWindows = WindowPlacement.atEnd
    static let defaultHiddenAppWindows = WindowPlacement.atEnd
    static let defaultScreens = ScreenChoice.all

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

    private static func read<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:))
    }
}

/// What to list, captured on the main thread when the switcher opens.
struct ListingOptions: Sendable {
    var minimizedWindows: WindowPlacement
    var hiddenAppWindows: WindowPlacement
    /// Screen frames in CoreGraphics coordinates (origin at the top left of
    /// the main display).
    var screens: [CGRect] = []
    /// Only windows on this screen, an index into `screens`. Nil for all screens.
    var onlyScreen: Int?

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
    static func current() -> ListingOptions {
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
            screens: screens,
            onlyScreen: AppSettings.screens == .withMouse ? mouseScreen : nil
        )
    }
}
