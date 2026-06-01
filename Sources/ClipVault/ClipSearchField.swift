import SwiftUI
import AppKit

/// An NSSearchField wrapper that forwards arrow keys, Return, and
/// Cmd+Delete to closures so the list can be driven from the search box.
struct ClipSearchField: NSViewRepresentable {
    @Binding var text: String
    var onMoveDown: () -> Void
    var onMoveUp: () -> Void
    var onSubmit: () -> Void
    var onSubmitPlain: () -> Void
    var onDelete: () -> Void
    var onPreview: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = KeyForwardingSearchField()
        field.placeholderString = "Search clipboard…"
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.onMoveDown = onMoveDown
        field.onMoveUp = onMoveUp
        field.onSubmit = onSubmit
        field.onSubmitPlain = onSubmitPlain
        field.onDelete = onDelete
        field.onPreview = onPreview
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let parent: ClipSearchField
        init(_ parent: ClipSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
    }
}

/// Search field subclass that intercepts navigation keys before they reach
/// the field editor.
final class KeyForwardingSearchField: NSSearchField {
    var onMoveDown: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onSubmitPlain: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 125: // down arrow
            onMoveDown?()
            return
        case 126: // up arrow
            onMoveUp?()
            return
        case 36, 76: // return / enter
            if event.modifierFlags.contains(.shift) {
                onSubmitPlain?()
            } else {
                onSubmit?()
            }
            return
        case 49 where stringValue.isEmpty: // space, only when search is empty
            onPreview?()
            return
        case 51 where event.modifierFlags.contains(.command): // Cmd+Delete
            onDelete?()
            return
        default:
            super.keyDown(with: event)
        }
    }
}
