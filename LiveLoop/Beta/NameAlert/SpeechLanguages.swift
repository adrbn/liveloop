//
//  SpeechLanguages.swift
//  LiveLoop
//
//  Beta (name alert) — the languages this Mac can transcribe offline. Name
//  alert never falls back to server recognition, so these are the only ones
//  it can use; Settings lists exactly these instead of a fixed guess.
//

import Foundation
import Speech

struct SpeechLanguage: Identifiable, Hashable {
    /// Locale identifier as stored in settings, e.g. "fr-FR".
    let id: String
    let name: String
}

struct SpeechLanguageOptions {
    /// The Mac's own language, e.g. "French".
    let systemName: String
    let systemAvailableOffline: Bool
    let languages: [SpeechLanguage]

    /// Takes around half a second (it loads every recognizer): call it off
    /// the main thread.
    static func load() -> SpeechLanguageOptions {
        let display = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let languages = SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .map { SpeechLanguage(id: $0.identifier, name: displayName(of: $0.identifier)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let system = systemLocale
        let systemCode = system.language.languageCode?.identifier ?? system.identifier
        return SpeechLanguageOptions(
            systemName: display.localizedString(forLanguageCode: systemCode) ?? system.identifier,
            systemAvailableOffline: SFSpeechRecognizer(locale: system)?.supportsOnDeviceRecognition == true,
            languages: languages)
    }

    /// The Mac's language: the first one in System Settings ▸ General ▸
    /// Language & Region. Not `Locale.current` — LiveLoop's interface is
    /// English-only, so its own locale always speaks English.
    static var systemLocale: Locale {
        Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
    }

    func contains(_ id: String) -> Bool {
        languages.contains { $0.id == id }
    }

    /// "German (Germany)" for "de-DE", in the interface language.
    static func displayName(of id: String) -> String {
        let display = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return display.localizedString(forIdentifier: id) ?? id
    }
}
