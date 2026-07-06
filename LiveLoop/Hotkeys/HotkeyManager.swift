//
//  HotkeyManager.swift
//  LiveLoop
//
//  System-wide hotkey to flip between live and loop without touching the meeting
//  app — a free "Pro" feature. Uses Carbon's RegisterEventHotKey, which fires
//  globally without needing Accessibility permission.
//

import Foundation
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {

    /// Invoked on the main thread when the hotkey fires.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // Routes the C callback back to the active instance.
    private static weak var active: HotkeyManager?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        HotkeyManager.active = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                DispatchQueue.main.async { HotkeyManager.active?.onTrigger?() }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C_4C_4B_59) /* 'LLKY' */, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Display

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_P: return "P"
        case kVK_Space: return "Space"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        default: return "Key\(keyCode)"
        }
    }
}
