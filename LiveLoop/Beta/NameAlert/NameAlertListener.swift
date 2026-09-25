//
//  NameAlertListener.swift
//  LiveLoop
//
//  Beta (name alert) — streams audio into Apple's speech recognizer with
//  on-device recognition *required* (no audio or text leaves the Mac) and
//  reports the first trigger word it hears. Recognition sessions are recycled
//  every ~50 s and after each match so transcripts stay short.
//

import Foundation
import AVFoundation
import Speech
import os.log

private let logger = Logger(subsystem: "com.adrbn.LiveLoop", category: "NameAlert")

enum NameAlertError: LocalizedError {
    case speechDenied
    case microphoneDenied
    case recognizerUnavailable(String)
    case onDeviceUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .speechDenied:
            return "Name alert needs Speech Recognition — allow LiveLoop in System Settings ▸ Privacy & Security ▸ Speech Recognition."
        case .microphoneDenied:
            return "Name alert needs the microphone — allow LiveLoop in System Settings ▸ Privacy & Security ▸ Microphone."
        case .recognizerUnavailable(let language):
            return "Speech recognition isn't available for \(language)."
        case .onDeviceUnsupported(let language):
            return "On-device speech recognition isn't available for \(language) on this Mac, so name alert stays off (it never sends audio online)."
        }
    }
}

final class NameAlertListener: @unchecked Sendable {

    private static let sessionLength: TimeInterval = 50
    private static let retryDelay: TimeInterval = 2
    /// A name at the very end of what's been heard counts once the recognizer
    /// has left it alone this long (you said it, then a pause).
    private static let settleDelay: TimeInterval = 1

    private let recognizer: SFSpeechRecognizer
    private let matcher: NameMatcher
    private let source: NameAlertAudioSource
    private let onMatch: @Sendable (String) -> Void
    private let resampler = MonoResampler()
    private let queue = DispatchQueue(label: "com.adrbn.LiveLoop.namealert")
    private let lock = NSLock()

    // Guarded by `lock` (the audio thread reads the current request).
    private var request: SFSpeechAudioBufferRecognitionRequest?
    // Only touched on `queue`.
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var resultCount = 0
    private var sessionTimer: DispatchSourceTimer?
    private var running = false

    init(matcher: NameMatcher, source: NameAlertAudioSource, locale: Locale,
         onMatch: @escaping @Sendable (String) -> Void) throws {
        let language = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw NameAlertError.recognizerUnavailable(language)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw NameAlertError.onDeviceUnsupported(language)
        }
        self.recognizer = recognizer
        self.matcher = matcher
        self.source = source
        self.onMatch = onMatch
    }

    static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func start() throws {
        queue.sync {
            running = true
            beginSession()
        }
        do {
            try source.start { [weak self] buffer in self?.append(buffer) }
        } catch {
            stop()
            throw error
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.sessionLength, repeating: Self.sessionLength)
        timer.setEventHandler { [weak self] in self?.restartSession() }
        timer.resume()
        queue.sync { sessionTimer = timer }
    }

    func stop() {
        source.stop()
        queue.sync {
            running = false
            sessionTimer?.cancel()
            sessionTimer = nil
            endSession()
        }
    }

    // MARK: - Audio thread

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let mono = resampler.convert(buffer) else { return }
        let request = lock.withLock { self.request }
        request?.append(mono)
    }

    // MARK: - Sessions (on `queue`)

    private func beginSession() {
        guard running else { return }
        generation += 1
        let current = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = matcher.recognizerHints
        lock.withLock { self.request = request }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.queue.async { self?.handle(result: result, error: error, generation: current) }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation current: Int) {
        guard running, current == generation else { return }
        resultCount += 1
        let transcript = result?.bestTranscription.formattedString ?? ""
        if let result, let trigger = matcher.firstSettledMatch(in: transcript, isFinal: result.isFinal) {
            fire(trigger)
        } else if let error {
            logger.debug("Recognition session ended: \(error.localizedDescription, privacy: .public)")
            endSession()
            queue.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
                guard let self, current == self.generation else { return }
                self.beginSession()
            }
        } else if result?.isFinal == true {
            restartSession()
        } else if let trigger = matcher.firstMatch(in: transcript) {
            fireIfUnrevised(trigger, resultCount: resultCount, generation: current)
        }
    }

    /// The name is the last word heard so far: wait for the recognizer to
    /// either move on (handled above) or leave it as is.
    private func fireIfUnrevised(_ trigger: String, resultCount count: Int, generation current: Int) {
        queue.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self, self.running, current == self.generation, count == self.resultCount else { return }
            self.fire(trigger)
        }
    }

    private func fire(_ trigger: String) {
        onMatch(trigger)
        restartSession()   // start clean so the same sentence can't match twice
    }

    private func restartSession() {
        endSession()
        beginSession()
    }

    private func endSession() {
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
            defer { self.request = nil }
            return self.request
        }
        request?.endAudio()
        task?.cancel()
        task = nil
    }
}
