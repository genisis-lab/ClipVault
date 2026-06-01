import Foundation
import AppKit
import ServiceManagement

/// Launch-at-login control via the modern SMAppService API (macOS 13+).
enum LoginItem {
    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("ClipVault: failed to update login item: \(error)")
            return false
        }
    }
}

/// Accessibility permission is required to synthesize the Cmd+V keystroke
/// for auto-paste. Hotkey registration itself does not need it.
enum AccessibilityPermission {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user (shows the system dialog) if not yet trusted.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
