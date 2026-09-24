import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "SpaceTab Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            // Size to the SwiftUI content first, so centering uses the real size.
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            self.window = window
        }
        // SpaceTab has no Dock icon, so bring it forward for the window to take focus.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Hand focus back to the app you were in. Otherwise SpaceTab stays the
        // active app with no window, and keys you press go nowhere.
        if NSApp.isActive {
            NSApp.hide(nil)
        }
    }
}
