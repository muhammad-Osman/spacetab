import AppKit
import ScreenCaptureKit

/// Captures window previews for the Thumbnails style and remembers the last
/// one of each window. Minimized windows can't be captured, so they show the
/// preview from before they were minimized.
@MainActor
final class ThumbnailStore {
    private static let limit = 200

    private var images: [CGWindowID: CGImage] = [:]
    /// Oldest first, to drop the oldest previews when over the limit.
    private var insertionOrder: [CGWindowID] = []

    func cached(_ id: CGWindowID) -> CGImage? {
        images[id]
    }

    /// Captures the on-screen windows among `windows`, and calls `update` with
    /// each window's index and preview as it arrives. Does nothing without
    /// Screen Recording permission. Cancel the returned task when the
    /// switcher closes.
    func capture(
        _ windows: [WindowInfo],
        maxPixelWidth: Int,
        update: @escaping @MainActor (Int, CGImage) -> Void
    ) -> Task<Void, Never>? {
        guard ScreenRecordingPermission.isGranted else { return nil }
        let targets = windows.enumerated()
            .filter { $0.element.state == .normal }
            .map { (index: $0.offset, id: $0.element.id) }
        guard !targets.isEmpty else { return nil }

        return Task { [weak self] in
            guard
                let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
                !Task.isCancelled
            else { return }
            let windowsByID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

            await withTaskGroup(of: (index: Int, id: CGWindowID, image: CGImage?).self) { group in
                for target in targets {
                    guard let window = windowsByID[target.id] else { continue }
                    group.addTask {
                        (target.index, target.id, await Self.captureImage(of: window, maxPixelWidth: maxPixelWidth))
                    }
                }
                for await result in group {
                    guard !Task.isCancelled, let image = result.image else { continue }
                    self?.store(image, for: result.id)
                    update(result.index, image)
                }
            }
        }
    }

    private func store(_ image: CGImage, for id: CGWindowID) {
        if images.updateValue(image, forKey: id) == nil {
            insertionOrder.append(id)
        }
        if insertionOrder.count > Self.limit {
            let dropped = insertionOrder.removeFirst()
            images[dropped] = nil
        }
    }

    private nonisolated static func captureImage(of window: SCWindow, maxPixelWidth: Int) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        // Windows are captured at up to 2 pixels per point, scaled down to the cell.
        let scale = min(2, CGFloat(maxPixelWidth) / frame.width)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(frame.width * scale))
        configuration.height = max(1, Int(frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
