import Foundation
import Carbon.HIToolbox
import AppKit

/// Registers a single system-wide hotkey using the Carbon Hot Key API.
/// This works without Accessibility permission (that's only needed to
/// *synthesize* keystrokes, not to receive a registered hotkey).
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    private static var instances: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier mask (e.g. `cmdKey | optionKey`).
    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.instances[id] = self
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let instance = GlobalHotKey.instances[hkID.id] {
                instance.handler()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x43_4C_56_54 /* 'CLVT' */), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        GlobalHotKey.instances[id] = nil
    }
}
