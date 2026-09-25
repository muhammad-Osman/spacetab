import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Screen Recording permission, needed only for the Thumbnails style.
///
/// macOS answers `CGPreflightScreenCaptureAccess` for the state at launch:
/// after the user grants the permission it stays false until SpaceTab is
/// reopened. So once the permission has been asked for, a live check with
/// ScreenCaptureKit decides instead.
@MainActor
enum ScreenRecordingPermission {
    private static let requestedKey = "screenRecordingRequested"
    private static let probeTimeout: TimeInterval = 2

    /// The last known answer. Refresh it with `refresh()`.
    private(set) static var isGranted = CGPreflightScreenCaptureAccess()

    /// Whether the user has been asked, so a live check shows no dialog.
    static var wasRequested: Bool {
        UserDefaults.standard.bool(forKey: requestedKey)
    }

    /// Shows the macOS permission dialog the first time, and opens the
    /// Screen Recording settings where the user switches SpaceTab on.
    static func request() {
        UserDefaults.standard.set(true, forKey: requestedKey)
        if CGRequestScreenCaptureAccess() {
            isGranted = true
        } else {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks the system again. Shows no dialog: the live check only runs once
    /// the user has been asked.
    static func refresh() async {
        if CGPreflightScreenCaptureAccess() {
            isGranted = true
        } else if wasRequested {
            isGranted = await probe()
        } else {
            isGranted = false
        }
    }

    /// Talks to ScreenCaptureKit outside a switch. That also lets macOS show
    /// its periodic "still allow?" reminder at a calm moment rather than in
    /// the middle of ⌥ Tab.
    static func warmUp() async {
        guard isGranted else { return }
        isGranted = await probe()
    }

    /// Quits and reopens SpaceTab, which macOS needs before a newly granted
    /// permission takes effect.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    /// Whether ScreenCaptureKit answers: listing windows fails without the permission.
    private static func probe() async -> Bool {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                (try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)) != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(probeTimeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            // No answer in time counts as granted: the permission wasn't refused.
            return first ?? true
        }
    }
}
