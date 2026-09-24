import AppKit

@main
@MainActor
enum SpaceTabApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        // Menu bar app: no Dock icon, even when run outside the app bundle.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
