import AppKit
import Sparkle

extension Notification.Name {
    /// Posted when an update becomes available or was dealt with.
    static let updateAvailabilityChanged = Notification.Name("SpaceTabUpdateAvailabilityChanged")
}

/// Checks GitHub Releases for new versions, through Sparkle. The feed URL and
/// the public key that updates are signed with come from Info.plist.
///
/// SpaceTab has no Dock icon and is rarely the active app, so Sparkle's
/// usual update window for a scheduled check would open behind other apps.
/// Instead, a scheduled update is announced in the menu bar menu, and the
/// window appears when the user asks for it.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    /// The version a scheduled check found, until the user has looked at it.
    private(set) var availableUpdate: String? {
        didSet { NotificationCenter.default.post(name: .updateAvailabilityChanged, object: nil) }
    }

    /// Whether updates can be checked for. Not when running outside the app
    /// bundle, which has no feed URL or key.
    var isAvailable: Bool { controller != nil }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        guard !feed.isEmpty, !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        do {
            try controller.updater.start()
            self.controller = controller
        } catch {
            NSLog("SpaceTab: updates unavailable: \(error.localizedDescription)")
        }
    }

    /// Checks now and shows the result, even when there is no update.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Only show the window when SpaceTab is already in front; otherwise the menu announces it.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.availableUpdate = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.availableUpdate = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.availableUpdate = nil }
    }
}
