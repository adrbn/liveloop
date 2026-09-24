//
//  BetaSettings.swift
//  LiveLoop
//
//  Preferences for the beta features. Every one of them is off by default and
//  changes nothing until it's switched on in Settings ▸ Beta. Stored in the
//  same App Group defaults as `Settings`, under a `beta.` prefix.
//

import Foundation

enum NameAlertSource: String, CaseIterable, Identifiable {
    case meetingAudio
    case microphone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meetingAudio: return "Meeting audio"
        case .microphone: return "Microphone"
        }
    }

    /// What this source actually hears, in one line.
    var detail: String {
        switch self {
        case .meetingAudio: return "Hears what your Mac plays, even with headphones on."
        case .microphone: return "Hears the room, so the meeting must play through your speakers."
        }
    }
}

@MainActor
final class BetaSettings: ObservableObject {

    private let defaults = LiveLoop.sharedDefaults

    // Loop timer & reminder
    @Published var loopTimerEnabled: Bool {
        didSet { defaults.set(loopTimerEnabled, forKey: Key.loopTimer) }
    }
    /// 0 = never remind.
    @Published var reminderMinutes: Int {
        didSet { defaults.set(reminderMinutes, forKey: Key.reminderMinutes) }
    }

    // Automations (Shortcuts + liveloop:// links)
    @Published var automationsEnabled: Bool {
        didSet { defaults.set(automationsEnabled, forKey: Key.automations) }
    }

    // Auto away / return
    @Published var autoAwayEnabled: Bool {
        didSet { defaults.set(autoAwayEnabled, forKey: Key.autoAway) }
    }
    @Published var autoAwaySeconds: Double {
        didSet { defaults.set(autoAwaySeconds, forKey: Key.autoAwaySeconds) }
    }
    @Published var autoReturnEnabled: Bool {
        didSet { defaults.set(autoReturnEnabled, forKey: Key.autoReturn) }
    }

    // Smart switch
    @Published var smartSwitchEnabled: Bool {
        didSet { defaults.set(smartSwitchEnabled, forKey: Key.smartSwitch) }
    }

    // Connection profile
    @Published var connectionProfile: ConnectionProfile {
        didSet { defaults.set(connectionProfile.rawValue, forKey: Key.connectionProfile) }
    }

    // Name alert
    @Published var nameAlertEnabled: Bool {
        didSet { defaults.set(nameAlertEnabled, forKey: Key.nameAlert) }
    }
    @Published var nameAlertTriggers: String {
        didSet { defaults.set(nameAlertTriggers, forKey: Key.nameAlertTriggers) }
    }
    @Published var nameAlertSource: NameAlertSource {
        didSet { defaults.set(nameAlertSource.rawValue, forKey: Key.nameAlertSource) }
    }
    /// A locale identifier such as "fr-FR"; empty = the system language.
    @Published var nameAlertLanguage: String {
        didSet { defaults.set(nameAlertLanguage, forKey: Key.nameAlertLanguage) }
    }

    init() {
        loopTimerEnabled = defaults.bool(forKey: Key.loopTimer)
        reminderMinutes = defaults.integer(forKey: Key.reminderMinutes)
        automationsEnabled = defaults.bool(forKey: Key.automations)
        autoAwayEnabled = defaults.bool(forKey: Key.autoAway)
        autoAwaySeconds = defaults.object(forKey: Key.autoAwaySeconds) as? Double ?? 10
        autoReturnEnabled = defaults.object(forKey: Key.autoReturn) as? Bool ?? true
        smartSwitchEnabled = defaults.bool(forKey: Key.smartSwitch)
        connectionProfile = defaults.string(forKey: Key.connectionProfile)
            .flatMap(ConnectionProfile.init(rawValue:)) ?? .off
        nameAlertEnabled = defaults.bool(forKey: Key.nameAlert)
        nameAlertTriggers = defaults.string(forKey: Key.nameAlertTriggers) ?? ""
        nameAlertSource = defaults.string(forKey: Key.nameAlertSource)
            .flatMap(NameAlertSource.init(rawValue:)) ?? .meetingAudio
        nameAlertLanguage = defaults.string(forKey: Key.nameAlertLanguage) ?? ""
    }

    private enum Key {
        static let loopTimer = "beta.loopTimer"
        static let reminderMinutes = "beta.reminderMinutes"
        static let automations = "beta.automations"
        static let autoAway = "beta.autoAway"
        static let autoAwaySeconds = "beta.autoAwaySeconds"
        static let autoReturn = "beta.autoReturn"
        static let smartSwitch = "beta.smartSwitch"
        static let connectionProfile = "beta.connectionProfile"
        static let nameAlert = "beta.nameAlert"
        static let nameAlertTriggers = "beta.nameAlertTriggers"
        static let nameAlertSource = "beta.nameAlertSource"
        static let nameAlertLanguage = "beta.nameAlertLanguage"
    }
}
