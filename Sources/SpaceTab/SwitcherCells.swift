import AppKit

/// One window in the switcher. Subclasses draw each style.
class SwitcherCell: NSView {
    let windowInfo: WindowInfo
    /// Called when the mouse moves over the cell, and when it is clicked.
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet { updateAppearance() }
    }

    init(window: WindowInfo, frame: NSRect) {
        windowInfo = window
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func updateAppearance() {
        layer?.backgroundColor = isSelected ? cgColor(.controlAccentColor) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Active always: the switcher never becomes the active app.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    /// Moving the mouse selects; the cell under the mouse when the switcher
    /// opens is not selected until the mouse moves.
    override func mouseMoved(with event: NSEvent) {
        onHover?()
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    /// Layer colors don't follow the theme on their own; resolve them for this view.
    func cgColor(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    /// "Minimized" or "Hidden" for windows off screen, nil otherwise.
    var stateText: String? {
        switch windowInfo.state {
        case .normal: nil
        case .minimized: "Minimized"
        case .appHidden: "Hidden"
        case .otherDesktop: "Other desktop"
        }
    }

    /// Whether the window is minimized or its app hidden, then the app name
    /// (unless the title already is the app name). The state comes first, so
    /// a long app name is what gets cut off.
    var detail: String {
        let appName = windowInfo.title.isEmpty ? "" : windowInfo.appName
        return [stateText ?? "", appName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

/// The cells of one style, placed in a document view with the origin at the top left.
@MainActor
struct CellLayout {
    let cells: [SwitcherCell]
    let contentSize: CGSize
    /// Whether the selected window's title is shown under the cells.
    var showsTitleBelow = false
}

// MARK: - Titles

/// A row with the app icon, window title and app name.
final class TitleCell: SwitcherCell {
    private static let width: CGFloat = 536
    private static let height: CGFloat = 32
    private static let gap: CGFloat = 2

    private let titleLabel: NSTextField
    private let detailLabel: NSTextField

    init(window: WindowInfo, frame: NSRect, scale: CGFloat) {
        titleLabel = Self.label(window.displayTitle, size: 13 * scale)
        detailLabel = Self.label("", size: 12 * scale)
        super.init(window: window, frame: frame)
        layer?.cornerRadius = 6 * scale

        let iconSize = 20 * scale
        let detailWidth = 150 * scale
        let icon = NSImageView(frame: NSRect(x: 8, y: (frame.height - iconSize) / 2, width: iconSize, height: iconSize))
        icon.image = window.icon
        icon.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.sizeToFit()
        let titleX = icon.frame.maxX + 10
        titleLabel.frame = NSRect(
            x: titleX,
            y: (frame.height - titleLabel.frame.height) / 2,
            width: frame.width - titleX - detailWidth - 16,
            height: titleLabel.frame.height
        )

        detailLabel.stringValue = detail
        detailLabel.alignment = .right
        detailLabel.sizeToFit()
        detailLabel.frame = NSRect(
            x: frame.width - detailWidth - 10,
            y: (frame.height - detailLabel.frame.height) / 2,
            width: detailWidth,
            height: detailLabel.frame.height
        )

        [icon, titleLabel, detailLabel].forEach(addSubview)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateAppearance() {
        super.updateAppearance()
        if isSelected {
            titleLabel.textColor = .white
        } else {
            titleLabel.textColor = windowInfo.state == .normal ? .labelColor : .secondaryLabelColor
        }
        detailLabel.textColor = isSelected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
    }

    static func layout(for windows: [WindowInfo], appearance: SwitcherAppearance) -> CellLayout {
        let width = Self.width * appearance.scale
        let height = Self.height * appearance.scale
        let step = height + gap * appearance.spacingFactor
        let cells = windows.enumerated().map { index, window in
            TitleCell(
                window: window,
                frame: NSRect(x: 0, y: CGFloat(index) * step, width: width, height: height),
                scale: appearance.scale
            )
        }
        let contentHeight = windows.isEmpty ? 0 : CGFloat(windows.count - 1) * step + height
        return CellLayout(cells: cells, contentSize: CGSize(width: width, height: contentHeight))
    }
}

// MARK: - App Icons

/// A large app icon. The selected window's title is shown under the row.
final class IconCell: SwitcherCell {
    private static let size: CGFloat = 96
    private static let iconSize: CGFloat = 72
    private static let spacing: CGFloat = 4

    init(window: WindowInfo, frame: NSRect, scale: CGFloat) {
        super.init(window: window, frame: frame)
        layer?.cornerRadius = 12 * scale
        let iconSize = Self.iconSize * scale
        let inset = (frame.width - iconSize) / 2
        let icon = NSImageView(frame: NSRect(x: inset, y: inset, width: iconSize, height: iconSize))
        icon.image = window.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Minimized windows and windows of hidden apps are drawn dimmer.
        icon.alphaValue = window.state == .normal ? 1 : 0.5
        addSubview(icon)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateAppearance() {
        layer?.backgroundColor = isSelected ? cgColor(NSColor.controlAccentColor.withAlphaComponent(0.6)) : nil
    }

    static func layout(for windows: [WindowInfo], availableWidth: CGFloat, appearance: SwitcherAppearance) -> CellLayout {
        let size = Self.size * appearance.scale
        let grid = GridLayout.fixed(
            count: windows.count,
            cellSize: CGSize(width: size, height: size),
            spacing: spacing * appearance.spacingFactor,
            availableWidth: availableWidth
        )
        let cells = windows.enumerated().map { index, window in
            IconCell(window: window, frame: grid.frame(ofCell: index), scale: appearance.scale)
        }
        return CellLayout(cells: cells, contentSize: grid.contentSize, showsTitleBelow: true)
    }
}

// MARK: - Thumbnails

/// A preview of the window with its app icon and title above it.
final class ThumbnailCell: SwitcherCell {
    private static let spacing: CGFloat = 10
    private static let titleHeight: CGFloat = 26
    private static let aspectRatio: CGFloat = 0.625
    private static let inset: CGFloat = 6

    private let titleLabel: NSTextField
    private let preview = NSImageView()
    private let placeholder = NSImageView()

    init(window: WindowInfo, frame: NSRect, cached: CGImage?, scale: CGFloat) {
        titleLabel = Self.label(window.displayTitle, size: 12 * scale, weight: .medium)
        super.init(window: window, frame: frame)

        let inset = Self.inset
        let titleHeight = Self.titleHeight * scale
        let iconSize = 16 * scale
        let titleY = frame.height - titleHeight + (titleHeight - iconSize) / 2 - 2
        let icon = NSImageView(frame: NSRect(x: inset, y: titleY, width: iconSize, height: iconSize))
        icon.image = window.icon
        icon.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(
            x: icon.frame.maxX + 5,
            y: titleY + (iconSize - titleLabel.frame.height) / 2,
            width: frame.width - icon.frame.maxX - 5 - inset,
            height: titleLabel.frame.height
        )
        let previewFrame = NSRect(x: inset, y: inset, width: frame.width - 2 * inset, height: frame.height - titleHeight - inset)
        preview.frame = previewFrame
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.alphaValue = window.state == .normal ? 1 : 0.6

        // Shown until a preview arrives, and for windows that can't be captured.
        let placeholderSize = min(64, previewFrame.height * 0.6)
        placeholder.frame = NSRect(
            x: previewFrame.midX - placeholderSize / 2,
            y: previewFrame.midY - placeholderSize / 2,
            width: placeholderSize,
            height: placeholderSize
        )
        placeholder.image = window.icon
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.alphaValue = 0.7

        [placeholder, preview, icon, titleLabel].forEach(addSubview)
        if let stateText {
            let badge = Self.label(stateText, size: 10, weight: .semibold)
            badge.textColor = .white
            badge.drawsBackground = true
            badge.backgroundColor = NSColor.black.withAlphaComponent(0.55)
            badge.sizeToFit()
            badge.frame = NSRect(
                x: previewFrame.minX + 4,
                y: previewFrame.minY + 4,
                width: badge.frame.width + 8,
                height: badge.frame.height + 2
            )
            badge.alignment = .center
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.masksToBounds = true
            addSubview(badge)
        }
        if let cached {
            setPreview(cached)
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setPreview(_ image: CGImage) {
        preview.image = NSImage(cgImage: image, size: .zero)
        placeholder.isHidden = true
    }

    override func updateAppearance() {
        layer?.backgroundColor = isSelected ? cgColor(NSColor.controlAccentColor.withAlphaComponent(0.7)) : nil
        titleLabel.textColor = isSelected ? .white : .labelColor
    }

    @MainActor
    static func layout(
        for windows: [WindowInfo],
        available: CGSize,
        thumbnails: ThumbnailStore,
        appearance: SwitcherAppearance
    ) -> (CellLayout, CGSize) {
        let scale = appearance.scale
        let grid = GridLayout.fitting(
            count: windows.count,
            in: available,
            spacing: spacing * appearance.spacingFactor,
            aspectRatio: aspectRatio,
            extraHeight: titleHeight * scale + inset,
            minCellWidth: 150 * scale,
            maxCellWidth: 320 * scale
        )
        let cells = windows.enumerated().map { index, window in
            ThumbnailCell(window: window, frame: grid.frame(ofCell: index), cached: thumbnails.cached(window.id), scale: scale)
        }
        return (CellLayout(cells: cells, contentSize: grid.contentSize, showsTitleBelow: true), grid.cellSize)
    }
}
