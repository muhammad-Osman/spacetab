import AppKit
import Sparkle

/// Checks GitHub Releases for new versions, through Sparkle. The feed URL and
/// the public key that updates are signed with come from Info.plist.
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?

    /// Whether updates can be checked for. Not when running outside the app
    /// bundle, which has no feed URL or key.
    var isAvailable: Bool { controller != nil }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        guard !feed.isEmpty, !key.isEmpty else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
        } catch {
            NSLog("SpaceTab: updates unavailable: \(error.localizedDescription)")
            self.controller = nil
        }
    }

    /// Checks now and shows the result, even when there is no update.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
