import Foundation
import AppKit
import Carbon.HIToolbox

/// Writes a history item back to the system pasteboard and (optionally)
/// synthesizes a Cmd+V keystroke so it lands in the frontmost app.
@MainActor
enum PasteEngine {

    /// Place the item on the general pasteboard. Returns true on success.
    /// When `asPlainText` is true, rich-text items are written as plain text
    /// only (formatting stripped) — useful for pasting into formatted editors.
    @discardableResult
    static func writeToPasteboard(_ item: ClipboardItem,
                                  store: HistoryStore,
                                  asPlainText: Bool = false) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text:
            return pb.setString(item.text, forType: .string)

        case .richText:
            if asPlainText {
                return pb.setString(item.text, forType: .string)
            }
            var ok = false
            if let rtf = item.rtfData {
                ok = pb.setData(rtf, forType: .rtf)
            }
            // Always include a plain-text fallback.
            ok = pb.setString(item.text, forType: .string) || ok
            return ok

        case .image:
            guard let url = store.imageURL(for: item),
                  let data = try? Data(contentsOf: url) else { return false }
            return pb.setData(data, forType: .png)

        case .fileURLs:
            let urls = item.fileURLStrings.compactMap { URL(string: $0) }
            guard !urls.isEmpty else { return false }
            return pb.writeObjects(urls as [NSPasteboardWriting])
        }
    }

    /// Synthesize a Cmd+V key press into whatever app is now frontmost.
    /// Requires Accessibility permission; callers should ensure that first.
    static func synthesizePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        let loc = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}
