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

    private let pipeline: ImagePipeline
    private let queue: DispatchQueue

    private var store: ClipFrameStore?
    private var sequencer = PingPongSequencer(frameCount: 0)
    private var lag = LagScheduler(intensity: 0, seed: 1)
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

    func start() {
        queue.async {
            guard self.store?.isEmpty == false, self.timer == nil else { return }
            self.sourceStep = 0
            // A fresh seed each run so the lag pattern never repeats between
            // sessions. Determinism (for tests) lives in LagScheduler itself.
            self.seedCounter &+= 1
            let seed = ExtensionDeviceSeed.mix(self.seedCounter)
            self.lag = LagScheduler(intensity: self.lagEnabled ? self.lagIntensity : 0, seed: seed)

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
        if lag.shouldAdvance() { sourceStep += 1 }
        let index = sequencer.index(for: sourceStep)
        let jpeg = store.frames[index]
        if let buffer = pipeline.decodeToOutput(jpeg) {
            onFrame?(buffer)
        }
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
