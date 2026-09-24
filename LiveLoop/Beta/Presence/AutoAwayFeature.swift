//
//  AutoAwayFeature.swift
//  LiveLoop
//
//  Beta — loop automatically when you leave the desk, and (optionally) go
//  live again when you sit back down. Deliberately conservative:
//
//  • it only auto-loops from live, with the camera on, a clip saved and no
//    recording in progress;
//  • it only auto-returns from a loop *it* started — a loop you started by
//    hand is never ended for you.
//

import Foundation
import Combine

@MainActor
final class AutoAwayFeature {

    /// Once our request has loaded the clip, the loop still has to crossfade
    /// in; if it hasn't started this long after, it isn't coming.
    private static let autoLoopGrace: Duration = .seconds(2)

    private let settings: BetaSettings
    private let tap: LiveFrameTap
    private weak var host: BetaHost?
    private var sampler: FaceSampler?
    private var detector: PresenceDetector
    private var mode: FrameRouter.Mode = .idle
    private var autoLoopRequest: UUID?
    private var autoLoopActive = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: BetaSettings, tap: LiveFrameTap, host: BetaHost) {
        self.settings = settings
        self.tap = tap
        self.host = host
        self.detector = Self.makeDetector(settings)
        settings.$autoAwayEnabled
            .combineLatest(settings.$autoAwaySeconds, settings.$autoReturnEnabled)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsDidChange() }
            .store(in: &cancellables)
    }

    func modeDidChange(_ newMode: FrameRouter.Mode) {
        mode = newMode
        switch newMode {
        case .loop:
            autoLoopActive = autoLoopRequest != nil
        case .live, .idle:
            autoLoopActive = false
            detector.reset(at: Self.now)
        }
        autoLoopRequest = nil
        refresh()
    }

    // MARK: - Private

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static func makeDetector(_ settings: BetaSettings) -> PresenceDetector {
        PresenceDetector(awayAfter: settings.autoAwaySeconds, returnAfter: 1.5, startingAt: now)
    }

    private var shouldWatch: Bool {
        guard settings.autoAwayEnabled else { return false }
        switch mode {
        case .live: return true
        case .loop: return autoLoopActive && settings.autoReturnEnabled
        case .idle: return false
        }
    }

    private func settingsDidChange() {
        detector = Self.makeDetector(settings)
        refresh()
    }

    private func refresh() {
        if shouldWatch {
            startSampling()
        } else {
            stopSampling()
        }
    }

    private func startSampling() {
        guard sampler == nil else { return }
        let sampler = FaceSampler { [weak self] present, time in
            Task { @MainActor in self?.observe(present: present, at: time) }
        }
        tap.setConsumer { buffer in sampler.offer(buffer) }
        self.sampler = sampler
    }

    private func stopSampling() {
        guard sampler != nil else { return }
        tap.setConsumer(nil)
        sampler = nil
    }

    private func observe(present: Bool, at time: TimeInterval) {
        guard shouldWatch, let event = detector.observe(present: present, at: time) else { return }
        switch event {
        case .left: stepAway()
        case .returned: comeBack()
        }
    }

    private func stepAway() {
        guard let host, mode == .live, host.isEngaged, !host.isRecording, host.hasClips else { return }
        let request = UUID()
        autoLoopRequest = request
        host.notify(.info, "Looks like you stepped away — looping.", sticky: false)
        Task { [weak self] in
            // However long the clip takes to load, the loop it starts is ours.
            await host.goToLoop()
            try? await Task.sleep(for: Self.autoLoopGrace)
            if self?.autoLoopRequest == request { self?.autoLoopRequest = nil }
        }
    }

    private func comeBack() {
        guard let host, mode == .loop, autoLoopActive, settings.autoReturnEnabled else { return }
        host.goToLive()
        host.notify(.success, "Welcome back — you're live.", sticky: false)
    }
}
