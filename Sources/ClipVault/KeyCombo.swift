import Foundation
import Carbon.HIToolbox
import AppKit

/// A recorded global hotkey: a virtual key code plus Carbon modifier flags.
struct KeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// The shipping default: ⌥⌘V.
    static let `default` = KeyCombo(keyCode: UInt32(kVK_ANSI_V),
                                    carbonModifiers: UInt32(cmdKey | optionKey))

    /// Human-readable representation, e.g. "⌥⌘V".
    var displayString: String {
        KeyCodeTranslator.modifierString(carbonModifiers) + KeyCodeTranslator.keyName(keyCode)
    }

    /// Whether the combo includes at least one modifier. Registering a global
    /// hotkey without a modifier would swallow a bare key everywhere, so the
    /// recorder rejects modifier-less combos.
    var hasModifier: Bool {
        carbonModifiers & UInt32(cmdKey | optionKey | controlKey | shiftKey) != 0
    }

    /// If this combo collides with a well-known macOS system shortcut, returns
    /// a short human-readable description of the conflict; otherwise nil. This
    /// is a best-effort check against common defaults, not an exhaustive list.
    var systemConflict: String? {
        let cmd = carbonModifiers & UInt32(cmdKey) != 0
        let opt = carbonModifiers & UInt32(optionKey) != 0
        let ctrl = carbonModifiers & UInt32(controlKey) != 0
        let shift = carbonModifiers & UInt32(shiftKey) != 0
        let key = Int(keyCode)

        // ⌘Space / ⌃Space — Spotlight / input source.
        if key == kVK_Space {
            if cmd && !opt && !ctrl { return "Spotlight (⌘Space)" }
            if ctrl && !cmd { return "input source switch (⌃Space)" }
        }
        // ⌘Tab — app switcher.
        if key == kVK_Tab && cmd { return "the app switcher (⌘Tab)" }
        // ⌘Q / ⌘W / ⌘H / ⌘M — fundamental app commands.
        if cmd && !opt && !ctrl && !shift {
            switch key {
            case kVK_ANSI_Q: return "Quit (⌘Q)"
            case kVK_ANSI_W: return "Close Window (⌘W)"
            case kVK_ANSI_H: return "Hide (⌘H)"
            case kVK_ANSI_M: return "Minimize (⌘M)"
            case kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A:
                return "a standard edit command"
            default: break
            }
        }
        // ⌘⇧3 / ⌘⇧4 / ⌘⇧5 — screenshots.
        if cmd && shift && !opt && !ctrl {
            if key == kVK_ANSI_3 || key == kVK_ANSI_4 || key == kVK_ANSI_5 {
                return "screenshots (⌘⇧3/4/5)"
            }
        }
        return nil
    }
}

/// Converts between AppKit modifier flags, Carbon modifier masks, and the
/// glyphs used to display a shortcut.
enum KeyCodeTranslator {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        return result
    }

    static func modifierString(_ carbon: UInt32) -> String {
        var s = ""
        if carbon & UInt32(controlKey) != 0 { s += "⌃" }
        if carbon & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbon & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbon & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    static func keyName(_ keyCode: UInt32) -> String {
        keyNames[Int(keyCode)] ?? "Key \(keyCode)"
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]
}
