/// Which window is highlighted in the switcher. Moving past either end wraps around.
struct SwitcherSelection: Equatable {
    let count: Int
    private(set) var index: Int

    /// Opening forwards selects the second window, the one used before the
    /// current one, so a quick ⌥ Tab flips between the last two windows.
    /// Opening backwards (⌥ ⇧ Tab) selects the last window.
    init(count: Int, openingBackwards: Bool) {
        self.count = count
        if count == 0 {
            index = 0
        } else if openingBackwards {
            index = count - 1
        } else {
            index = min(1, count - 1)
        }
    }

    mutating func move(by delta: Int) {
        guard count > 0 else { return }
        index = ((index + delta) % count + count) % count
    }
}
