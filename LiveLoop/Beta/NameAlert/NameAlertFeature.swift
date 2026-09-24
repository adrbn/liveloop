//
//  NameAlertFeature.swift
//  LiveLoop
//
//  Beta — "someone said your name". Listens only while you're on the loop,
//  only when switched on, and only with on-device speech recognition. When a
//  trigger word is heard: a chime, a notification and a banner telling you
//  how to go live.
//

import Foundation
import AppKit
import AVFoundation
import Speech
import Combine

@MainActor
final class NameAlertFeature {

    private static let cooldownSeconds: TimeInterval = 20

    /// Starting and stopping audio capture are slow round-trips to Core Audio:
    /// they run here, off the main thread and strictly in order.
    private let control = DispatchQueue(label: "com.adrbn.LiveLoop.namealert.control", qos: .userInitiated)
    private let settings: BetaSettings
    private let notifier: BetaNotifier
    private weak var host: BetaHost?
    private var listener: NameAlertListener?
    private var startAttempt = 0
    private var mode: FrameRouter.Mode = .idle
    private var cooldown = AlertCooldown(interval: cooldownSeconds)
    private var cancellables = Set<AnyCancellable>()

    init(settings: BetaSettings, notifier: BetaNotifier, host: BetaHost) {
        self.settings = settings
        self.notifier = notifier
        self.host = host
        settings.$nameAlertEnabled
            .combineLatest(settings.$nameAlertTriggers, settings.$nameAlertSource, settings.$nameAlertLanguage)
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)   // typing in the names field
            .sink { [weak self] _ in self?.restart() }
            .store(in: &cancellables)
    }

    func modeDidChange(_ newMode: FrameRouter.Mode) {
        mode = newMode
        refresh()
    }

    /// Plays the full alert once so you know what it sounds like.
    func testAlert() {
        alert(heard: NameMatcher(rawTriggers: settings.nameAlertTriggers).triggers.first ?? "your name")
    }

    // MARK: - Private

    private var matcher: NameMatcher { NameMatcher(rawTriggers: settings.nameAlertTriggers) }

    private var shouldListen: Bool {
        settings.nameAlertEnabled && mode == .loop && !matcher.triggers.isEmpty
    }

    private func restart() {
        stopListening()
        refresh()
    }

    private func refresh() {
        if shouldListen {
            startListening()
        } else {
            stopListening()
        }
    }

    private func startListening() {
        guard listener == nil else { return }
        startAttempt += 1
        let attempt = startAttempt
        Task {
            do {
                try await ensurePermissions()
                // Things may have changed while a permission prompt was up.
                guard attempt == startAttempt, shouldListen, listener == nil else { return }
                let listener = try makeListener()
                self.listener = listener
                control.async { [weak self] in
                    do {
                        try listener.start()
                    } catch {
                        Task { @MainActor in self?.startFailed(error, attempt: attempt) }
                    }
                }
            } catch {
                guard attempt == startAttempt else { return }
                host?.notify(.failure, error.localizedDescription, sticky: true)
            }
        }
    }

    private func startFailed(_ error: Error, attempt: Int) {
        guard attempt == startAttempt else { return }
        listener = nil
        host?.notify(.failure, error.localizedDescription, sticky: true)
    }

    private func stopListening() {
        startAttempt += 1
        guard let listener else { return }
        self.listener = nil
        control.async { listener.stop() }
    }

    private func ensurePermissions() async throws {
        await NameAlertPermissions.request(for: settings.nameAlertSource)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw NameAlertError.speechDenied }
        if settings.nameAlertSource == .microphone {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw NameAlertError.microphoneDenied }
        }
    }

    private func makeListener() throws -> NameAlertListener {
        let language = settings.nameAlertLanguage
        let locale = language.isEmpty ? SpeechLanguageOptions.systemLocale : Locale(identifier: language)
        let source = try NameAlertAudio.makeSource(settings.nameAlertSource)
        return try NameAlertListener(matcher: matcher, source: source, locale: locale) { [weak self] trigger in
            Task { @MainActor in self?.heard(trigger) }
        }
    }

    private func heard(_ trigger: String) {
        guard listener != nil, cooldown.shouldFire(at: Date()) else { return }
        alert(heard: trigger)
    }

    private func alert(heard trigger: String) {
        NSSound(named: "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSSound(named: "Glass")?.play() }
        let hotkey = host?.hotkeyDisplay ?? "the shortcut"
        notifier.post(id: "liveloop.name-alert",
                      title: "Someone said “\(trigger)”",
                      body: "You're still on the loop. Press \(hotkey) to go live.")
        host?.notify(.info, "Someone said “\(trigger)” — press \(hotkey) to go live.", sticky: true)
    }
}
