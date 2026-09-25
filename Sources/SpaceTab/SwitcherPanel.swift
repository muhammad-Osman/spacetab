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
    private static let searchBarHeight: CGFloat = 34
    private static let minWidthWithBar: CGFloat = 360

    /// Called with the index of the cell the mouse moved over, or clicked.
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let thumbnails = ThumbnailStore()
    private let background = NSVisualEffectView()
    private let tint = NSView()
    private let scrollView = NSScrollView()
    private let titleBelow = NSTextField(labelWithString: "")
    private let searchField = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No matching windows")
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
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.masksToBounds = true
        contentView = background

        // Drawn over the blur: the more opaque, the more solid the switcher looks.
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        background.addSubview(tint)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        background.addSubview(scrollView)

        titleBelow.font = .systemFont(ofSize: 13, weight: .medium)
        titleBelow.alignment = .center
        titleBelow.lineBreakMode = .byTruncatingMiddle
        background.addSubview(titleBelow)

        searchField.font = .systemFont(ofSize: 14)
        searchField.lineBreakMode = .byTruncatingHead
        background.addSubview(searchField)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        background.addSubview(emptyLabel)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the windows on `screen`. `search` is the current search text, or nil when not searching.
    func show(
        _ windows: [WindowInfo],
        selectedIndex: Int,
        style: SwitcherStyle,
        search: String?,
        appearance: SwitcherAppearance,
        on screen: NSScreen?
    ) {
        let wasVisible = isVisible
        captureTask?.cancel()
        captureTask = nil
        if style != .thumbnails || !ScreenRecordingPermission.isGranted {
            // No screen contents are kept beyond what the style and the permission allow.
            thumbnails.clear()
        }
        // Overlay scrollers take no width from the cells. Set on every show,
        // because the scroll view goes back to the system style when that
        // preference changes (for example when a mouse is plugged in).
        scrollView.scrollerStyle = .overlay
        applyAppearance(appearance)

        let screen = screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let barHeight = search != nil ? Self.searchBarHeight : 0
        // Whole points, so nothing is drawn between pixels.
        let available = CGSize(
            width: (visible.width * Self.maxWidthFraction - 2 * Self.padding).rounded(.down),
            height: (visible.height * Self.maxHeightFraction - 2 * Self.padding - barHeight).rounded(.down)
        )

        var thumbnailSize: CGSize?
        let layout: CellLayout
        switch style {
        case .titles:
            layout = TitleCell.layout(for: windows, appearance: appearance)
        case .appIcons:
            layout = IconCell.layout(for: windows, availableWidth: available.width, appearance: appearance)
        case .thumbnails:
            (layout, thumbnailSize) = ThumbnailCell.layout(
                for: windows, available: available, thumbnails: thumbnails, appearance: appearance
            )
        }
        cells = layout.cells
        for (index, cell) in cells.enumerated() {
            cell.onHover = { [weak self] in self?.onHover?(index) }
            cell.onClick = { [weak self] in self?.onClick?(index) }
        }

        let document = FlippedView(frame: NSRect(origin: .zero, size: layout.contentSize))
        cells.forEach(document.addSubview)
        scrollView.documentView = document

        let belowHeight = layout.showsTitleBelow ? Self.titleBelowHeight : 0
        let isEmpty = windows.isEmpty
        let shown = CGSize(
            width: isEmpty ? 0 : min(layout.contentSize.width, available.width),
            height: isEmpty ? 40 : min(layout.contentSize.height, available.height - belowHeight)
        )
        let minWidth = layout.showsTitleBelow || search != nil ? Self.minWidthWithBar : 0
        let size = CGSize(
            width: max(shown.width + 2 * Self.padding, minWidth),
            height: shown.height + belowHeight + barHeight + 2 * Self.padding
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
        emptyLabel.isHidden = !isEmpty
        emptyLabel.frame = NSRect(x: Self.padding, y: Self.padding + belowHeight + 10, width: size.width - 2 * Self.padding, height: 20)
        titleBelow.isHidden = !layout.showsTitleBelow
        titleBelow.frame = NSRect(x: Self.padding, y: Self.padding + 4, width: size.width - 2 * Self.padding, height: 20)

        searchField.isHidden = search == nil
        if let search {
            searchField.stringValue = "Search: \(search)"
            searchField.frame = NSRect(
                x: Self.padding + 4,
                y: size.height - Self.padding - barHeight + 6,
                width: size.width - 2 * Self.padding - 8,
                height: 22
            )
        }

        self.selectedIndex = selectedIndex
        select(selectedIndex)

        if !wasVisible {
            fadeIn(duration: appearance.fadeDuration)
        }
        orderFrontRegardless()

        if let thumbnailSize {
            let scale = screen?.backingScaleFactor ?? 2
            let maxPixelSize = CGSize(width: thumbnailSize.width * scale, height: thumbnailSize.height * scale)
            captureTask = thumbnails.capture(windows, selectedIndex: selectedIndex, maxPixelSize: maxPixelSize) { [weak self] index, image in
                guard let self, let cell = self.cells[safe: index] as? ThumbnailCell else { return }
                cell.setPreview(image)
            }
        }
    }

    /// The cell one row above (`rowDelta` -1) or below (+1) `index`, wrapping
    /// around: the one whose center is nearest horizontally. In a single
    /// column, the previous or next cell.
    func index(from index: Int, rowDelta: Int) -> Int {
        guard cells.indices.contains(index) else { return index }
        let rows = Dictionary(grouping: cells.indices) { cells[$0].frame.minY }
        let rowTops = rows.keys.sorted()
        guard rowTops.count > 1, let row = rowTops.firstIndex(of: cells[index].frame.minY) else {
            return ((index + rowDelta) % cells.count + cells.count) % cells.count
        }
        let targetRow = ((row + rowDelta) % rowTops.count + rowTops.count) % rowTops.count
        let midX = cells[index].frame.midX
        return rows[rowTops[targetRow]]!.min { abs(cells[$0].frame.midX - midX) < abs(cells[$1].frame.midX - midX) }!
    }

    func select(_ index: Int) {
        guard cells.indices.contains(index) else {
            titleBelow.stringValue = ""
            return
        }
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

    private func applyAppearance(_ appearance: SwitcherAppearance) {
        self.appearance = switch appearance.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        background.layer?.cornerRadius = appearance.cornerRadius
        // The tint is the window background color; the blur shows through the rest.
        var tintColor = NSColor.windowBackgroundColor.withAlphaComponent(appearance.opacity)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tintColor = NSColor.windowBackgroundColor.withAlphaComponent(appearance.opacity)
        }
        tint.layer?.backgroundColor = tintColor.cgColor
        tint.frame = background.bounds
    }

    private func fadeIn(duration: TimeInterval) {
        guard duration > 0 else {
            alphaValue = 1
            return
        }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
        }
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
