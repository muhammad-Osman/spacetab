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
    private var previewPanel: SelectedPreviewPanel?
    private var previewGeneration = 0
    private var switcherAppearance = SwitcherAppearance()
    private let background = NSVisualEffectView()
    private let tint = NSView()
    private let scrollView = NSScrollView()
    private let titleBelow = NSTextField(labelWithString: "")
    private let searchField = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: String(localized: "No matching windows"))
    private var cells: [SwitcherCell] = []
    private var selectedIndex = 0

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
        setAccessibilityLabel(String(localized: "Window switcher"))

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
        thumbnails.stop()
        if (style != .thumbnails && !appearance.showsSelectedPreview) || !ScreenRecordingPermission.isGranted {
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
            // The selected window's title goes under the grid; leave room for it.
            let gridArea = CGSize(width: available.width, height: available.height - Self.titleBelowHeight)
            (layout, thumbnailSize) = ThumbnailCell.layout(
                for: windows, available: gridArea, thumbnails: thumbnails, appearance: appearance
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
            searchField.stringValue = String(localized: "Search: \(search)")
            searchField.frame = NSRect(
                x: Self.padding + 4,
                y: size.height - Self.padding - barHeight + 6,
                width: size.width - 2 * Self.padding - 8,
                height: 22
            )
        }

        self.selectedIndex = selectedIndex

        orderFrontRegardless()
        select(selectedIndex)

        if !wasVisible {
            fadeIn(duration: appearance.fadeDuration)
        }

        if let thumbnailSize {
            let scale = screen?.backingScaleFactor ?? 2
            let maxPixelSize = CGSize(width: thumbnailSize.width * scale, height: thumbnailSize.height * scale)
            thumbnails.capture(windows, selectedIndex: selectedIndex, maxPixelSize: maxPixelSize) { [weak self] index, image in
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
            updateSelectedPreview()
            return
        }
        cells[safe: selectedIndex]?.isSelected = false
        selectedIndex = index
        let cell = cells[index]
        cell.isSelected = true
        cell.scrollToVisible(cell.bounds)
        NSAccessibility.post(element: cell, notification: .focusedUIElementChanged)
        let detail = cell.detail
        titleBelow.stringValue = detail.isEmpty ? cell.windowInfo.displayTitle : "\(cell.windowInfo.displayTitle) — \(detail)"
        updateSelectedPreview()
    }

    override func orderOut(_ sender: Any?) {
        previewGeneration += 1
        thumbnails.stop()
        previewPanel?.orderOut(nil)
        super.orderOut(sender)
    }

    private func applyAppearance(_ appearance: SwitcherAppearance) {
        switcherAppearance = appearance
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

    private func updateSelectedPreview() {
        guard switcherAppearance.showsSelectedPreview,
              cells.indices.contains(selectedIndex),
              let screen = screenForPreview
        else {
            previewGeneration += 1
            previewPanel?.orderOut(nil)
            return
        }
        let window = cells[selectedIndex].windowInfo
        let placeholder = window.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage()
        let image = thumbnails.cached(window.id).map { NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height)) } ?? placeholder
        let preview = previewPanel ?? SelectedPreviewPanel()
        previewPanel = preview
        preview.show(image: image, below: self, on: screen, appearance: switcherAppearance)

        previewGeneration += 1
        let generation = previewGeneration
        guard window.isOnScreen else { return }
        let maximum = CGSize(width: screen.visibleFrame.width * 0.45, height: screen.visibleFrame.height * 0.45)
        let scale = screen.backingScaleFactor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.previewGeneration == generation,
                  self.cells.indices.contains(self.selectedIndex),
                  self.cells[self.selectedIndex].windowInfo.id == window.id
            else { return }
            self.thumbnails.captureOne(window, maxPixelSize: CGSize(width: maximum.width * scale, height: maximum.height * scale)) { [weak self] image in
                guard let self, self.previewGeneration == generation,
                      self.cells.indices.contains(self.selectedIndex),
                      self.cells[self.selectedIndex].windowInfo.id == window.id,
                      let screen = self.screenForPreview
                else { return }
                self.previewPanel?.show(
                    image: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)),
                    below: self,
                    on: screen,
                    appearance: self.switcherAppearance
                )
            }
        }
    }

    private var screenForPreview: NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
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

/// A non-interactive visual companion to the switcher, kept below it in the
/// window order so it never takes focus or intercepts a click.
@MainActor
private final class SelectedPreviewPanel: NSPanel {
    private static let padding: CGFloat = 8
    private static let gap: CGFloat = 8
    private let background = NSVisualEffectView()
    private let tint = NSView()
    private let imageView = NSImageView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        setAccessibilityElement(false)

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.masksToBounds = true
        background.setAccessibilityElement(false)
        contentView = background

        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        tint.setAccessibilityElement(false)
        background.addSubview(tint)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityElement(false)
        background.addSubview(imageView)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(image: NSImage, below switcher: NSPanel, on screen: NSScreen, appearance: SwitcherAppearance) {
        self.appearance = switch appearance.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        background.layer?.cornerRadius = appearance.cornerRadius
        var tintColor = NSColor.windowBackgroundColor.withAlphaComponent(appearance.opacity)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tintColor = NSColor.windowBackgroundColor.withAlphaComponent(appearance.opacity)
        }
        tint.layer?.backgroundColor = tintColor.cgColor

        let visible = screen.visibleFrame
        let maximum = CGSize(
            width: max(0, visible.width * 0.45 - 2 * Self.padding),
            height: max(0, visible.height * 0.45 - 2 * Self.padding)
        )
        let sourceSize = image.size.width > 0 && image.size.height > 0 ? image.size : CGSize(width: 160, height: 100)
        let imageSize = PreviewLayout.fittedSize(imageSize: sourceSize, in: maximum)
        let size = CGSize(width: imageSize.width + 2 * Self.padding, height: imageSize.height + 2 * Self.padding)
        let x = visible.midX - size.width / 2
        let belowY = switcher.frame.minY - Self.gap - size.height
        let y: CGFloat
        if belowY >= visible.minY {
            y = belowY
        } else {
            y = min(visible.maxY - size.height, switcher.frame.maxY + Self.gap)
        }
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        tint.frame = background.bounds
        imageView.image = image
        imageView.frame = NSRect(x: Self.padding, y: Self.padding, width: imageSize.width, height: imageSize.height)
        order(.below, relativeTo: switcher.windowNumber)
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
