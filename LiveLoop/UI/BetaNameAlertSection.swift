//
//  BetaNameAlertSection.swift
//  LiveLoop
//
//  Settings ▸ Beta ▸ Name alert. Turning it on fills in your first name from
//  your Mac account and asks for Speech Recognition right then, not mid-meeting.
//  The language list is what this Mac can actually transcribe offline.
//

import SwiftUI
import AppKit

struct BetaNameAlertSection: View {
    @ObservedObject var settings: BetaSettings
    let controller: BetaController

    @State private var languages: SpeechLanguageOptions?
    @State private var permissionProblem: NameAlertPermissions.Problem?

    var body: some View {
        Section {
            Toggle(isOn: $settings.nameAlertEnabled.animation()) {
                FeatureLabel(title: "Name alert",
                             subtitle: "Tells you when someone says your name while you're on the loop.",
                             symbol: "person.wave.2", tint: .green)
            }
            if settings.nameAlertEnabled {
                options
            }
        } header: {
            Text("Stay Reachable")
        } footer: {
            if settings.nameAlertEnabled {
                Text("Speech is transcribed on this Mac and is never recorded or sent anywhere. It only listens while you're on the loop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: settings.nameAlertEnabled) { _, enabled in
            if enabled { didEnable() }
        }
        .onChange(of: settings.nameAlertSource) { _, _ in
            if settings.nameAlertEnabled { askForPermissions() }
        }
        .task(id: settings.nameAlertEnabled) {
            guard settings.nameAlertEnabled else { return }
            refreshPermissionProblem()
            if languages == nil {
                languages = await Task.detached(priority: .userInitiated) { SpeechLanguageOptions.load() }.value
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionProblem()   // back from System Settings
        }
    }

    @ViewBuilder
    private var options: some View {
        Group {
            // Bordered so the field is still visible when empty (no placeholder).
            TextField(text: $settings.nameAlertTriggers) {
                Text("Listen for")
                Text("Separate several names with commas.")
            }
            .textFieldStyle(.roundedBorder)
            if NameMatcher(rawTriggers: settings.nameAlertTriggers).triggers.isEmpty {
                InlineWarning(message: "Add at least one name to listen for.")
            }

            Picker(selection: $settings.nameAlertSource) {
                ForEach(NameAlertSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            } label: {
                Text("Listen to")
                Text(settings.nameAlertSource.detail)
            }

            languagePicker

            if let problem = permissionProblem {
                InlineWarning(message: problem.message,
                              actionTitle: problem.settingsURL == nil ? nil : "Open System Settings…",
                              action: problem.settingsURL.map { url in { NSWorkspace.shared.open(url) } })
            }

            LabeledContent("Hear what it sounds like") {
                Button("Play Test Alert") { controller.nameAlert.testAlert() }
            }
        }
        .padding(.leading, FeatureLabel.optionInset)
    }

    @ViewBuilder
    private var languagePicker: some View {
        if let languages {
            Picker("Language", selection: $settings.nameAlertLanguage) {
                Text(systemLanguageLabel(languages)).tag("")
                Divider()
                ForEach(languages.languages) { language in
                    Text(language.name).tag(language.id)
                }
                let current = settings.nameAlertLanguage
                if !current.isEmpty, !languages.contains(current) {
                    Text(SpeechLanguageOptions.displayName(of: current)).tag(current)   // explained just below
                }
            }
            if let warning = languageWarning(languages) {
                InlineWarning(message: warning)
            }
        } else {
            LabeledContent("Language") {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: Helpers

    private func systemLanguageLabel(_ options: SpeechLanguageOptions) -> String {
        options.systemAvailableOffline
            ? "Same as Mac (\(options.systemName))"
            : "Same as Mac (\(options.systemName), not available offline)"
    }

    private func languageWarning(_ options: SpeechLanguageOptions) -> String? {
        let current = settings.nameAlertLanguage
        let usable = current.isEmpty ? options.systemAvailableOffline : options.contains(current)
        return usable ? nil : "This Mac can't transcribe that language offline. Pick one from the list."
    }

    private func didEnable() {
        controller.requestNotificationPermission()
        if NameMatcher(rawTriggers: settings.nameAlertTriggers).triggers.isEmpty,
           let name = NameMatcher.suggestedTrigger(fromFullName: NSFullUserName()) {
            settings.nameAlertTriggers = name
        }
        askForPermissions()
    }

    private func askForPermissions() {
        Task {
            await NameAlertPermissions.request(for: settings.nameAlertSource)
            refreshPermissionProblem()
        }
    }

    private func refreshPermissionProblem() {
        permissionProblem = NameAlertPermissions.problem(for: settings.nameAlertSource)
    }
}
