import AppKit
@preconcurrency import ScreenCaptureKit

/// Captures window previews for the Thumbnails style and remembers the last
/// one of each window. Minimized windows can't be captured, so they show the
/// preview from before they were minimized.
@MainActor
final class ThumbnailStore {
    private static let limit = 60
    /// How many captures run at once. Each one costs the system a capture
    /// session, and too many at once stall screenshots system-wide.
    private static let maxConcurrentCaptures = 4
    private static let captureTimeout: TimeInterval = 4
    private static let contentTimeout: TimeInterval = 2
    /// How long the list of capturable windows is reused between opens.
    private static let contentMaxAge: TimeInterval = 3

    private var images: [CGWindowID: CGImage] = [:]
    /// Least recently used first, to drop old previews when over the limit.
    private var recentOrder: [CGWindowID] = []
    private var content: (windows: [CGWindowID: SCWindow], date: Date)?

    func cached(_ id: CGWindowID) -> CGImage? {
        guard let image = images[id] else { return nil }
        markUsed(id)
        return image
    }

    /// Forgets every preview.
    func clear() {
        images = [:]
        recentOrder = []
        content = nil
    }

    /// Captures the on-screen windows among `windows`, the selected one
    /// first, and calls `update` with each window's index and preview as it
    /// arrives. Does nothing without Screen Recording permission. Cancel the
    /// returned task when the switcher closes: captures already started
    /// still finish and are kept for later, but no new ones start.
    func capture(
        _ windows: [WindowInfo],
        selectedIndex: Int,
        maxPixelSize: CGSize,
        update: @escaping @MainActor (Int, CGImage) -> Void
    ) -> Task<Void, Never>? {
        guard ScreenRecordingPermission.isGranted else { return nil }
        var targets = windows.enumerated()
            .filter { $0.element.isOnScreen }
            .map { (index: $0.offset, id: $0.element.id) }
        if let first = targets.firstIndex(where: { $0.index == selectedIndex }) {
            targets.insert(targets.remove(at: first), at: 0)
        }
        guard !targets.isEmpty else { return nil }

        return Task { [weak self] in
            // Windows that no longer exist don't need a preview any more.
            let liveIDs = Set(
                (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
                    .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
            )
            self?.prune(keeping: liveIDs)

            guard let self, let capturable = await self.capturableWindows(for: targets.map(\.id)) else { return }

            await withTaskGroup(of: (index: Int, id: CGWindowID, image: CGImage?).self) { group in
                var pending = targets.filter { capturable[$0.id] != nil }
                func startNext() {
                    guard !Task.isCancelled, !pending.isEmpty else { return }
                    let target = pending.removeFirst()
                    let window = capturable[target.id]!
                    group.addTask {
                        (target.index, target.id, await Self.captureImage(of: window, maxPixelSize: maxPixelSize))
                    }
                }
                for _ in 0..<Self.maxConcurrentCaptures {
                    startNext()
                }
                for await result in group {
                    if let image = result.image {
                        // Kept even after the switcher closed, for when the window is minimized.
                        self.store(image, for: result.id)
                        if !Task.isCancelled {
                            update(result.index, image)
                        }
                    }
                    startNext()
                }
            }
        }
    }

    /// The capturable windows, by ID. Reuses the last list while it is fresh
    /// and has every window asked for.
    private func capturableWindows(for ids: [CGWindowID]) async -> [CGWindowID: SCWindow]? {
        if let content, Date().timeIntervalSince(content.date) < Self.contentMaxAge,
           ids.allSatisfy({ content.windows[$0] != nil }) {
            return content.windows
        }
        guard let windows = await Self.shareableWindows() else { return nil }
        content = (windows, Date())
        return windows
    }

    private func prune(keeping liveIDs: Set<CGWindowID>) {
        images = images.filter { liveIDs.contains($0.key) }
        recentOrder.removeAll { !liveIDs.contains($0) }
    }

    private func store(_ image: CGImage, for id: CGWindowID) {
        images[id] = image
        markUsed(id)
        while recentOrder.count > Self.limit, let oldest = recentOrder.first {
            recentOrder.removeFirst()
            images[oldest] = nil
        }
    }

    private func markUsed(_ id: CGWindowID) {
        recentOrder.removeAll { $0 == id }
        recentOrder.append(id)
    }

    /// Lists the windows ScreenCaptureKit can capture. Nil when it doesn't
    /// answer in time, for example while a permission dialog is up.
    private nonisolated static func shareableWindows() async -> [CGWindowID: SCWindow]? {
        await withTaskGroup(of: [CGWindowID: SCWindow]?.self) { group in
            group.addTask {
                guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
                    return nil
                }
                return Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(contentTimeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// One window's picture, at most `maxPixelSize`, or nil when the capture
    /// fails or takes too long.
    private nonisolated static func captureImage(of window: SCWindow, maxPixelSize: CGSize) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        // Windows are captured at up to 2 pixels per point, scaled down to the cell.
        let scale = min(2, maxPixelSize.width / frame.width, maxPixelSize.height / frame.height)
        let width = max(1, Int(frame.width * scale))
        let height = max(1, Int(frame.height * scale))
        let filter = SCContentFilter(desktopIndependentWindow: window)

        return await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                if #available(macOS 26, *) {
                    let configuration = SCScreenshotConfiguration()
                    configuration.width = width
                    configuration.height = height
                    configuration.showsCursor = false
                    configuration.ignoreShadows = true
                    configuration.dynamicRange = .sdr
                    let output = try? await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
                    return output?.sdrImage
                } else {
                    let configuration = SCStreamConfiguration()
                    configuration.width = width
                    configuration.height = height
                    configuration.scalesToFit = true
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true
                    return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(captureTimeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
