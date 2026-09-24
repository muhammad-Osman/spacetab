import AppKit

/// One window in the switcher. Subclasses draw each style.
class SwitcherCell: NSView {
    let windowInfo: WindowInfo

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
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
    }

    /// "Minimized" or "Hidden" for windows off screen, nil otherwise.
    var stateText: String? {
        switch windowInfo.state {
        case .normal: nil
        case .minimized: "Minimized"
        case .appHidden: "Hidden"
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
    static let width: CGFloat = 536
    static let height: CGFloat = 32

    private let titleLabel: NSTextField
    private let detailLabel: NSTextField

    override init(window: WindowInfo, frame: NSRect) {
        titleLabel = Self.label(window.displayTitle, size: 13)
        detailLabel = Self.label("", size: 12)
        super.init(window: window, frame: frame)
        layer?.cornerRadius = 6

        let iconSize: CGFloat = 20
        let detailWidth: CGFloat = 150
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

    static func layout(for windows: [WindowInfo]) -> CellLayout {
        let cells = windows.enumerated().map { index, window in
            TitleCell(window: window, frame: NSRect(x: 0, y: CGFloat(index) * height, width: width, height: height))
        }
        return CellLayout(cells: cells, contentSize: CGSize(width: width, height: CGFloat(windows.count) * height))
    }
}

// MARK: - App Icons

/// A large app icon. The selected window's title is shown under the row.
final class IconCell: SwitcherCell {
    static let size: CGFloat = 96
    static let iconSize: CGFloat = 72
    static let spacing: CGFloat = 4

    override init(window: WindowInfo, frame: NSRect) {
        super.init(window: window, frame: frame)
        layer?.cornerRadius = 12
        let inset = (frame.width - Self.iconSize) / 2
        let icon = NSImageView(frame: NSRect(x: inset, y: inset, width: Self.iconSize, height: Self.iconSize))
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
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor : nil
    }

    static func layout(for windows: [WindowInfo], availableWidth: CGFloat) -> CellLayout {
        let grid = GridLayout.fixed(
            count: windows.count,
            cellSize: CGSize(width: size, height: size),
            spacing: spacing,
            availableWidth: availableWidth
        )
        let cells = windows.enumerated().map { index, window in
            IconCell(window: window, frame: grid.frame(ofCell: index))
        }
        return CellLayout(cells: cells, contentSize: grid.contentSize, showsTitleBelow: true)
    }
}

// MARK: - Thumbnails

/// A preview of the window with its app icon and title above it.
final class ThumbnailCell: SwitcherCell {
    static let spacing: CGFloat = 10
    static let titleHeight: CGFloat = 26
    static let aspectRatio: CGFloat = 0.625
    private static let inset: CGFloat = 6

    private let titleLabel: NSTextField
    private let preview = NSImageView()
    private let placeholder = NSImageView()

    init(window: WindowInfo, frame: NSRect, cached: CGImage?) {
        titleLabel = Self.label(window.displayTitle, size: 12, weight: .medium)
        super.init(window: window, frame: frame)

        let inset = Self.inset
        let iconSize: CGFloat = 16
        let titleY = frame.height - Self.titleHeight + (Self.titleHeight - iconSize) / 2 - 2
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
        titleLabel.toolTip = detail

        let previewFrame = NSRect(x: inset, y: inset, width: frame.width - 2 * inset, height: frame.height - Self.titleHeight - inset)
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
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor : nil
        titleLabel.textColor = isSelected ? .white : .labelColor
    }

    @MainActor
    static func layout(for windows: [WindowInfo], available: CGSize, thumbnails: ThumbnailStore) -> (CellLayout, CGSize) {
        let grid = GridLayout.fitting(
            count: windows.count,
            in: available,
            spacing: spacing,
            aspectRatio: aspectRatio,
            extraHeight: titleHeight + inset,
            minCellWidth: 150,
            maxCellWidth: 320
        )
        let cells = windows.enumerated().map { index, window in
            ThumbnailCell(window: window, frame: grid.frame(ofCell: index), cached: thumbnails.cached(window.id))
        }
        return (CellLayout(cells: cells, contentSize: grid.contentSize), grid.cellSize)
    }
}
