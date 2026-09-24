//
//  LoopEngine.swift
//  LiveLoop
//
//  Drives loop playback: a 30 fps timer that walks a clip's frames using the
//  ping-pong sequencer, optionally holding frames per the simulated-lag
//  scheduler, decodes the chosen frame, and hands the finished output buffer to
//  its `onFrame` callback (the FrameRouter).
//

import Foundation
import CoreVideo

final class LoopEngine {

    /// Called on the processing queue with each produced loop frame.
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// Simulated-lag configuration (a free "Pro" feature).
    var lagEnabled = false
    var lagIntensity = 0.5

    /// Beta: a Simulated lag style that replaces the stutter (see `LagEffects`).
    var connectionProfile: ConnectionProfile = .off

    private let pipeline: ImagePipeline
    private let queue: DispatchQueue

    private var store: ClipFrameStore?
    private var sequencer = PingPongSequencer(frameCount: 0)
    private var lag = LagScheduler(intensity: 0, seed: 1)
    private var connection = ConnectionSimulator(profile: .off, seed: 1)
    private var timer: DispatchSourceTimer?
    private var sourceStep = 0
    private var seedCounter: UInt64 = 0

    init(pipeline: ImagePipeline, queue: DispatchQueue) {
        self.pipeline = pipeline
        self.queue = queue
    }

    var isLoaded: Bool { !(store?.isEmpty ?? true) }

    func load(_ store: ClipFrameStore) {
        queue.async {
            self.store = store
            self.sequencer = PingPongSequencer(frameCount: store.count)
            self.sourceStep = 0
        }
    }

    /// Starts playback. `startFrame` (beta smart switch) picks the first frame
    /// shown; by default playback starts at the top of the clip.
    func start(atFrame startFrame: Int? = nil) {
        queue.async {
            guard self.store?.isEmpty == false, self.timer == nil else { return }
            // The first tick advances one step, so start one step before the chosen frame.
            self.sourceStep = startFrame.map { $0 - 1 } ?? 0
            // A fresh seed each run so the lag pattern never repeats between
            // sessions. Determinism (for tests) lives in LagScheduler itself.
            self.seedCounter &+= 1
            let seed = ExtensionDeviceSeed.mix(self.seedCounter)
            let effects = LagEffects(enabled: self.lagEnabled, intensity: self.lagIntensity,
                                     profile: self.connectionProfile)
            self.lag = LagScheduler(intensity: effects.stutterIntensity, seed: seed)
            self.connection = ConnectionSimulator(profile: effects.profile, seed: seed ^ 0xC0FF_EE00_D15E_A5E5)

            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / Double(LiveLoop.frameRate), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    private func tick() {
        guard let store, !store.isEmpty else { return }
        // `.pristine` (always advance, full quality) unless a beta profile is the lag style.
        let impairment = connection.next()
        if lag.shouldAdvance(), impairment.advance { sourceStep += 1 }
        let index = sequencer.index(for: sourceStep)
        let jpeg = store.frames[index]
        if let buffer = pipeline.decodeToOutput(jpeg) {
            let output = impairment.quality < 1 ? pipeline.degraded(buffer, quality: impairment.quality) : buffer
            onFrame?(output ?? buffer)
        }
    }

    // MARK: - Beta: smart switch (call on the processing queue)

    /// Monotonic playback position; the ping-pong frame is derived from it.
    var currentStep: Int { sourceStep }

    /// The clip frame that best matches `target`, or nil without signatures.
    func bestStartFrame(matching target: [UInt8]) -> Int? {
        guard let store else { return nil }
        return PoseMatcher.bestIndex(in: store.signatures, matching: target)
    }

    /// The step within `horizon` whose frame best matches `target`.
    func bestUpcomingStep(matching target: [UInt8], horizon: Int) -> Int {
        guard let store else { return sourceStep }
        return PoseMatcher.bestUpcomingStep(from: sourceStep, horizon: horizon, sequencer: sequencer,
                                            signatures: store.signatures, target: target)
    }
}

/// Derives a per-run seed without `Date`/`Math.random`, which are unavailable in
/// some contexts. Host time is fine here — determinism is provided by the seed,
/// not by the clock.
private enum ExtensionDeviceSeed {
    static func mix(_ counter: UInt64) -> UInt64 {
        let host = DispatchTime.now().uptimeNanoseconds
        return host ^ (counter &* 0x9E37_79B9_7F4A_7C15)
    }
}
