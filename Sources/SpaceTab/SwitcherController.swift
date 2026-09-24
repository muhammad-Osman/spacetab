import AppKit

private enum KeyCode {
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
}

/// Decides what each key press does and drives the switcher panel.
@MainActor
final class SwitcherController {
    private let panel = SwitcherPanel()
    private var windows: [WindowInfo] = []
    private var selection: SwitcherSelection?

    var isOpen: Bool { selection != nil }

    /// Handles one keyboard event. Returns `true` to swallow it.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch type {
        case .keyDown:
            if keyCode == KeyCode.tab, isSwitcherShortcut(flags) {
                let backwards = flags.contains(.maskShift)
                if isOpen {
                    move(by: backwards ? -1 : 1)
                } else {
                    open(backwards: backwards)
                }
                return true
            }
            guard isOpen else { return false }
            switch keyCode {
            case KeyCode.left, KeyCode.up: move(by: -1)
            case KeyCode.right, KeyCode.down: move(by: 1)
            case KeyCode.escape: close()
            default: break
            }
            // While the switcher is open, no key reaches the app behind it.
            return true

        case .keyUp:
            return isOpen

        case .flagsChanged:
            if isOpen, !flags.contains(.maskAlternate) {
                commit()
            }
            return false

        default:
            return false
        }
    }

    private func isSwitcherShortcut(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl)
    }

    private func open(backwards: Bool) {
        windows = WindowLister.windowsOnCurrentDesktop()
        guard !windows.isEmpty else { return }
        let selection = SwitcherSelection(count: windows.count, openingBackwards: backwards)
        self.selection = selection
        panel.show(windows, selectedIndex: selection.index)
    }

    private func move(by delta: Int) {
        guard var selection else { return }
        selection.move(by: delta)
        self.selection = selection
        panel.select(selection.index)
    }

    private func commit() {
        guard let selection else { return }
        let window = windows[selection.index]
        close()
        WindowActivator.activate(window)
    }

    private func close() {
        selection = nil
        windows = []
        panel.orderOut(nil)
    }
}
