//
//  Settings.swift
//  LiveLoop
//
//  User preferences, persisted to the shared App Group defaults so the camera
//  extension can read the ones it cares about (the virtual-camera name). Every
//  former "Pro" toggle lives here and is free.
//

import Foundation
import Carbon.HIToolbox

@MainActor
final class Settings: ObservableObject {

    private let defaults = LiveLoop.sharedDefaults

    @Published var cameraName: String {
        didSet { defaults.set(cameraName, forKey: LiveLoop.DefaultsKey.cameraName) }
    }
    @Published var selectedCameraID: String? {
        didSet { defaults.set(selectedCameraID, forKey: Key.selectedCameraID) }
    }
    @Published var recordDurationSeconds: Double {
        didSet { defaults.set(recordDurationSeconds, forKey: Key.recordDuration) }
    }
    @Published var lagEnabled: Bool {
        didSet { defaults.set(lagEnabled, forKey: Key.lagEnabled) }
    }
    @Published var lagIntensity: Double {
        didSet { defaults.set(lagIntensity, forKey: Key.lagIntensity) }
    }
    @Published var hotkeyEnabled: Bool {
        didSet { defaults.set(hotkeyEnabled, forKey: Key.hotkeyEnabled) }
    }
    @Published var hotkeyKeyCode: UInt32 {
        didSet { defaults.set(Int(hotkeyKeyCode), forKey: Key.hotkeyKeyCode) }
    }
    @Published var hotkeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotkeyModifiers), forKey: Key.hotkeyModifiers) }
    }
    @Published var autoEngageOnLaunch: Bool {
        didSet { defaults.set(autoEngageOnLaunch, forKey: Key.autoEngage) }
    }

    init() {
        cameraName = defaults.string(forKey: LiveLoop.DefaultsKey.cameraName) ?? LiveLoop.defaultCameraName
        selectedCameraID = defaults.string(forKey: Key.selectedCameraID)
        recordDurationSeconds = defaults.object(forKey: Key.recordDuration) as? Double ?? 6
        lagEnabled = defaults.bool(forKey: Key.lagEnabled)
        lagIntensity = defaults.object(forKey: Key.lagIntensity) as? Double ?? 0.5
        hotkeyEnabled = defaults.object(forKey: Key.hotkeyEnabled) as? Bool ?? true
        hotkeyKeyCode = UInt32(defaults.object(forKey: Key.hotkeyKeyCode) as? Int ?? kVK_ANSI_L)
        hotkeyModifiers = UInt32(defaults.object(forKey: Key.hotkeyModifiers) as? Int ?? Int(cmdKey | optionKey))
        autoEngageOnLaunch = defaults.bool(forKey: Key.autoEngage)
    }

    /// Human-readable form of the current hotkey, e.g. "⌥⌘L".
    var hotkeyDisplayString: String {
        HotkeyManager.displayString(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    private enum Key {
        static let selectedCameraID = "selectedCameraID"
        static let recordDuration = "recordDurationSeconds"
        static let lagEnabled = "lagEnabled"
        static let lagIntensity = "lagIntensity"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let autoEngage = "autoEngageOnLaunch"
    }
}
