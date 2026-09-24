import AppKit

/// The switcher on screen, in Titles style: one row per window with the app
/// icon, window title and app name.
///
/// A non-activating panel, so opening it never takes focus from the app you
/// are switching away from.
@MainActor
final class SwitcherPanel: NSPanel {
    private static let width: CGFloat = 560
    private static let rowHeight: CGFloat = 32
    private static let padding: CGFloat = 8
    private static let maxScreenFraction: CGFloat = 0.7

    private let scrollView = NSScrollView()
    private var rows: [SwitcherRowView] = []
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        contentView = background

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        background.addSubview(scrollView)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ windows: [WindowInfo], selectedIndex: Int) {
        // Overlay scrollers take no width from the rows. Set on every show,
        // because the scroll view goes back to the system style when that
        // preference changes (for example when a mouse is plugged in).
        scrollView.scrollerStyle = .overlay

        let rowWidth = Self.width - 2 * Self.padding
        let document = FlippedView(frame: NSRect(
            x: 0, y: 0, width: rowWidth, height: CGFloat(windows.count) * Self.rowHeight
        ))
        rows = windows.enumerated().map { index, window in
            let row = SwitcherRowView(window: window, frame: NSRect(
                x: 0, y: CGFloat(index) * Self.rowHeight, width: rowWidth, height: Self.rowHeight
            ))
            document.addSubview(row)
            return row
        }
        scrollView.documentView = document

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let height = min(document.frame.height, visible.height * Self.maxScreenFraction) + 2 * Self.padding
        let frame = NSRect(
            x: visible.midX - Self.width / 2,
            y: visible.midY - height / 2,
            width: Self.width,
            height: height
        )
        setFrame(frame, display: false)
        scrollView.frame = contentView!.bounds.insetBy(dx: Self.padding, dy: Self.padding)

        self.selectedIndex = selectedIndex
        rows[selectedIndex].isSelected = true
        rows[selectedIndex].scrollToVisible(rows[selectedIndex].bounds)
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[selectedIndex].isSelected = false
        selectedIndex = index
        rows[index].isSelected = true
        rows[index].scrollToVisible(rows[index].bounds)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SwitcherRowView: NSView {
    private let titleLabel: NSTextField
    private let appLabel: NSTextField

    var isSelected = false {
        didSet { updateColors() }
    }

    init(window: WindowInfo, frame: NSRect) {
        titleLabel = NSTextField(labelWithString: window.displayTitle)
        appLabel = NSTextField(labelWithString: window.title.isEmpty ? "" : window.appName)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6

        let iconSize: CGFloat = 20
        let appWidth: CGFloat = 150
        let iconView = NSImageView(frame: NSRect(
            x: 8, y: (frame.height - iconSize) / 2, width: iconSize, height: iconSize
        ))
        iconView.image = window.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.sizeToFit()
        let titleX = iconView.frame.maxX + 10
        titleLabel.frame = NSRect(
            x: titleX,
            y: (frame.height - titleLabel.frame.height) / 2,
            width: frame.width - titleX - appWidth - 16,
            height: titleLabel.frame.height
        )

        appLabel.font = .systemFont(ofSize: 12)
        appLabel.alignment = .right
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.sizeToFit()
        appLabel.frame = NSRect(
            x: frame.width - appWidth - 10,
            y: (frame.height - appLabel.frame.height) / 2,
            width: appWidth,
            height: appLabel.frame.height
        )

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(appLabel)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func updateColors() {
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
        titleLabel.textColor = isSelected ? .white : .labelColor
        appLabel.textColor = isSelected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
    }
}
