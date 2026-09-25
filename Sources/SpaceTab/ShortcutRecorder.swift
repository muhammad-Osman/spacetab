import AppKit
import SwiftUI

/// A button that shows a shortcut and records a new one when clicked: the
/// next key pressed with at least one modifier becomes the shortcut.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = { keyCode, modifiers in
            shortcut.keyCode = keyCode
            shortcut.modifiers = modifiers
        }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcutText = shortcut.displayText
    }

    final class RecorderView: NSView {
        var onRecord: ((Int64, Shortcut.Modifiers) -> Void)?
        var shortcutText = "" {
            didSet { updateTitle() }
        }

        private let button = NSButton(title: "", target: nil, action: nil)
        private var isRecording = false {
            didSet {
                updateTitle()
                MainActor.assumeIsolated { ShortcutSettings.isRecording = isRecording }
            }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            button.bezelStyle = .rounded
            button.target = self
            button.action = #selector(startRecording)
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.topAnchor.constraint(equalTo: topAnchor),
                button.bottomAnchor.constraint(equalTo: bottomAnchor),
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        deinit {
            if isRecording {
                MainActor.assumeIsolated { ShortcutSettings.isRecording = false }
            }
        }

        override var acceptsFirstResponder: Bool { true }

        @objc private func startRecording() {
            window?.makeFirstResponder(self)
            isRecording = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                isRecording = false
            }
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 {
                // Esc cancels.
                window?.makeFirstResponder(nil)
                return
            }
            let modifiers = Shortcut.Modifiers(flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            guard !modifiers.isEmpty else {
                NSSound.beep()
                return
            }
            onRecord?(Int64(event.keyCode), modifiers)
            window?.makeFirstResponder(nil)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Key presses with ⌘ or ⌃ arrive here instead of keyDown.
            guard isRecording, event.type == .keyDown else { return false }
            keyDown(with: event)
            return true
        }

        private func updateTitle() {
            button.title = isRecording ? "Press keys…" : shortcutText
        }
    }
}
