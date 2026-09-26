import AppKit
import SwiftUI

/// A button that shows a shortcut and records a new one when clicked: the
/// next key pressed with at least one modifier becomes the shortcut.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeNSView(context: Context) -> RecorderView {
        RecorderView()
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcutText = shortcut.displayText
        // Set on every update: the binding of a row in a list changes when
        // rows above it are removed.
        view.onRecord = { keyCode, modifiers in
            shortcut.keyCode = keyCode
            shortcut.modifiers = modifiers
        }
    }

    final class RecorderView: NSView {
        var onRecord: ((Int64, Shortcut.Modifiers) -> Void)?
        var shortcutText = "" {
            didSet { updateTitle() }
        }

        private let button = NSButton(title: "", target: nil, action: nil)
        private var windowTokens: [NSObjectProtocol] = []
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
            windowTokens.forEach(NotificationCenter.default.removeObserver)
            windowTokens = []
            if newWindow == nil {
                isRecording = false
            }
        }

        /// Recording ends when the window closes or another window or app
        /// takes over. Otherwise every key on the Mac would keep going to a
        /// recorder nobody can see.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                windowTokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopRecording() }
                })
            }
        }

        private func stopRecording() {
            guard isRecording else { return }
            if window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
            isRecording = false
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 {
                // Esc cancels.
                stopRecording()
                return
            }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            let modifiers = Shortcut.Modifiers(flags: flags, keyCode: Int64(event.keyCode))
            // At least one modifier that macOS reports reliably; Fn alone isn't enough.
            guard !modifiers.subtracting(.function).isEmpty else {
                NSSound.beep()
                return
            }
            onRecord?(Int64(event.keyCode), modifiers)
            stopRecording()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Key presses with ⌘ or ⌃ arrive here instead of keyDown.
            guard isRecording, event.type == .keyDown else { return false }
            keyDown(with: event)
            return true
        }

        private func updateTitle() {
            button.title = isRecording ? String(localized: "Press keys…") : shortcutText
        }
    }
}
