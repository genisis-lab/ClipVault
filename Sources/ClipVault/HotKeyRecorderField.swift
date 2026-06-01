import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A SwiftUI control that records a global hotkey. Click to begin recording,
/// then press the desired key combination. Escape cancels; a combo without a
/// modifier is rejected (a bare global key would be captured system-wide).
struct HotKeyRecorderField: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { newCombo in combo = newCombo }
        button.combo = combo
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.combo = combo
        nsView.refreshTitle()
    }

    /// An NSButton that toggles into a "listening" state and turns the next
    /// key-down with modifiers into a `KeyCombo`.
    final class RecorderButton: NSButton {
        var combo: KeyCombo = .default
        var onRecord: ((KeyCombo) -> Void)?
        private var isRecording = false
        private var monitor: Any?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(toggleRecording)
            refreshTitle()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func refreshTitle() {
            title = isRecording ? "Press shortcut… (⎋ to cancel)" : combo.displayString
        }

        @objc private func toggleRecording() {
            isRecording ? stopRecording() : startRecording()
        }

        private func startRecording() {
            isRecording = true
            refreshTitle()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)
                return nil
            }
        }

        private func stopRecording() {
            isRecording = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            refreshTitle()
        }

        private func handle(_ event: NSEvent) {
            // Escape cancels without changing the combo.
            if event.keyCode == kVK_Escape {
                stopRecording()
                return
            }
            let carbon = KeyCodeTranslator.carbonModifiers(from: event.modifierFlags)
            let candidate = KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
            guard candidate.hasModifier else {
                NSSound.beep()
                return
            }
            combo = candidate
            onRecord?(candidate)
            stopRecording()
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
