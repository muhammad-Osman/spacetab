import AppKit
import CoreGraphics

/// Screen Recording permission, needed only for the Thumbnails style.
enum ScreenRecordingPermission {
    /// Checks without asking.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the macOS permission dialog the first time, and opens the
    /// Screen Recording settings where the user switches SpaceTab on.
    static func request() {
        if !CGRequestScreenCaptureAccess() {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
