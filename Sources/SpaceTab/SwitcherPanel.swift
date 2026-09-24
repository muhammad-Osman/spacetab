import AppKit

/// The switcher on screen, in the chosen style.
///
/// A non-activating panel, so opening it never takes focus from the app you
/// are switching away from.
@MainActor
final class SwitcherPanel: NSPanel {
    private static let padding: CGFloat = 12
    private static let maxWidthFraction: CGFloat = 0.9
    private static let maxHeightFraction: CGFloat = 0.8
    private static let titleBelowHeight: CGFloat = 30
    private static let minWidthWithTitleBelow: CGFloat = 360

    private let thumbnails = ThumbnailStore()
    private let scrollView = NSScrollView()
    private let titleBelow = NSTextField(labelWithString: "")
    private var cells: [SwitcherCell] = []
    private var selectedIndex = 0
    private var captureTask: Task<Void, Never>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        background.addSubview(scrollView)

        titleBelow.font = .systemFont(ofSize: 13, weight: .medium)
        titleBelow.alignment = .center
        titleBelow.lineBreakMode = .byTruncatingMiddle
        background.addSubview(titleBelow)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ windows: [WindowInfo], selectedIndex: Int, style: SwitcherStyle) {
        captureTask?.cancel()
        captureTask = nil
        // Overlay scrollers take no width from the cells. Set on every show,
        // because the scroll view goes back to the system style when that
        // preference changes (for example when a mouse is plugged in).
        scrollView.scrollerStyle = .overlay

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let available = CGSize(
            width: visible.width * Self.maxWidthFraction - 2 * Self.padding,
            height: visible.height * Self.maxHeightFraction - 2 * Self.padding
        )

        var thumbnailSize: CGSize?
        let layout: CellLayout
        switch style {
        case .titles:
            layout = TitleCell.layout(for: windows)
        case .appIcons:
            layout = IconCell.layout(for: windows, availableWidth: available.width)
        case .thumbnails:
            (layout, thumbnailSize) = ThumbnailCell.layout(for: windows, available: available, thumbnails: thumbnails)
        }
        cells = layout.cells

        let document = FlippedView(frame: NSRect(origin: .zero, size: layout.contentSize))
        cells.forEach(document.addSubview)
        scrollView.documentView = document

        let belowHeight = layout.showsTitleBelow ? Self.titleBelowHeight : 0
        let shown = CGSize(
            width: min(layout.contentSize.width, available.width),
            height: min(layout.contentSize.height, available.height - belowHeight)
        )
        let minWidth = layout.showsTitleBelow ? Self.minWidthWithTitleBelow : 0
        let size = CGSize(
            width: max(shown.width + 2 * Self.padding, minWidth),
            height: shown.height + belowHeight + 2 * Self.padding
        )
        setFrame(
            NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height),
            display: false
        )
        scrollView.frame = NSRect(
            x: (size.width - shown.width) / 2,
            y: Self.padding + belowHeight,
            width: shown.width,
            height: shown.height
        )
        titleBelow.isHidden = !layout.showsTitleBelow
        titleBelow.frame = NSRect(x: Self.padding, y: Self.padding + 4, width: size.width - 2 * Self.padding, height: 20)

        self.selectedIndex = selectedIndex
        select(selectedIndex)
        orderFrontRegardless()

        if let thumbnailSize {
            let scale = screen?.backingScaleFactor ?? 2
            captureTask = thumbnails.capture(windows, maxPixelWidth: Int(thumbnailSize.width * scale)) { [weak self] index, image in
                guard let self, let cell = self.cells[safe: index] as? ThumbnailCell else { return }
                cell.setPreview(image)
            }
        }
    }

    func select(_ index: Int) {
        guard cells.indices.contains(index) else { return }
        cells[safe: selectedIndex]?.isSelected = false
        selectedIndex = index
        let cell = cells[index]
        cell.isSelected = true
        cell.scrollToVisible(cell.bounds)
        let detail = cell.detail
        titleBelow.stringValue = detail.isEmpty ? cell.windowInfo.displayTitle : "\(cell.windowInfo.displayTitle) — \(detail)"
    }

    override func orderOut(_ sender: Any?) {
        captureTask?.cancel()
        captureTask = nil
        super.orderOut(sender)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
