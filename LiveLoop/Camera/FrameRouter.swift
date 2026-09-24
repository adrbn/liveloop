//
//  FrameRouter.swift
//  LiveLoop
//
//  Decides which frame the virtual camera shows at any instant — the live
//  webcam or the loop — and performs a short crossfade when switching between
//  them so the transition never snaps. Everything here runs on the shared
//  processing queue, so no locking is required.
//

import Foundation
import CoreVideo
import CoreMedia

final class FrameRouter {

    enum Mode: Equatable {
        case idle   // not engaged; extension shows its placeholder
        case live   // forwarding the physical webcam
        case loop   // forwarding the loop
    }

    /// The loop source. Injected after construction (AppState owns both).
    var loopEngine: LoopEngine? {
        didSet { loopEngine?.onFrame = { [weak self] buffer in self?.handleLoopFrame(buffer) } }
    }

    /// Notified on the main queue whenever the effective mode changes.
    var onModeChange: ((Mode) -> Void)?

    /// Called (on the processing queue) with every frame emitted to the virtual
    /// camera — used to drive the in-app "what viewers see" preview.
    var onOutputFrame: ((CVPixelBuffer) -> Void)?

    private let pipeline: ImagePipeline
    private let publisher: SinkStreamPublisher
    private let queue: DispatchQueue

    private var mode: Mode = .idle
    private var latestLiveOutput: CVPixelBuffer?

    // Crossfade state (advanced once per loop tick).
    private var transitionActive = false
    private var transitionToLoop = false
    private var transitionProgress = 0.0
    private let transitionIncrement: Double

    // Beta (smart switch): a return to live waiting for the loop to line up with you.
    private var pendingLiveStep: Int?
    private var pendingLiveTicks = 0
    /// Look up to ~1.5 s ahead for a matching loop frame…
    private static let smartHorizonSteps = 45
    /// …but never keep someone waiting more than 2 s (freezes stall the step).
    private static let smartMaxWaitTicks = 60
    /// Start the crossfade slightly early so it's centred on the best match.
    private static let smartLeadSteps = 5

    init(pipeline: ImagePipeline, publisher: SinkStreamPublisher, queue: DispatchQueue) {
        self.pipeline = pipeline
        self.publisher = publisher
        self.queue = queue
        // ~0.35 s crossfade at the output frame rate.
        self.transitionIncrement = 1.0 / (0.35 * Double(LiveLoop.frameRate))
    }

    var currentMode: Mode { mode }

    // MARK: - Control (called from the main thread)

    func engageLive() {
        queue.async {
            self.transitionActive = false
            self.pendingLiveStep = nil
            self.setMode(.live)
        }
    }

    /// `smart` (beta) starts the loop on the frame that best matches you now.
    func goToLoop(smart: Bool = false) {
        queue.async {
            guard self.loopEngine?.isLoaded == true else { return }
            self.loopEngine?.start(atFrame: smart ? self.smartStartFrame() : nil)
            self.transitionActive = true
            self.transitionToLoop = true
            self.transitionProgress = 0
        }
    }

    /// `smart` (beta) waits up to 2 s for the loop to line up with you first.
    /// `togglesPendingReturn`: a toggle pressed again during that wait cancels
    /// it and stays on the loop.
    func goToLive(smart: Bool = false, togglesPendingReturn: Bool = false) {
        queue.async {
            guard self.mode == .loop || (self.transitionActive && self.transitionToLoop) else { return }
            if self.pendingLiveStep != nil {
                if togglesPendingReturn { self.pendingLiveStep = nil }
                return
            }
            if smart, self.mode == .loop, !self.transitionActive {
                if let step = self.smartReturnStep() {
                    self.pendingLiveStep = step
                    self.pendingLiveTicks = 0
                    return
                }
            }
            self.beginTransitionToLive()
        }
    }

    func disengage() {
        queue.async {
            self.transitionActive = false
            self.pendingLiveStep = nil
            self.loopEngine?.stop()
            self.latestLiveOutput = nil
            self.setMode(.idle)
        }
    }

    // MARK: - Frame handlers (on the processing queue)

    /// Sends a frame to the virtual camera and mirrors it to the preview.
    private func emit(_ buffer: CVPixelBuffer) {
        publisher.send(buffer)
        onOutputFrame?(buffer)
    }

    func handleLiveFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let scaled = pipeline.scaledToOutput(pixelBuffer)
        latestLiveOutput = scaled
        // Only the live path emits when we're steady-state live.
        if mode == .live, !transitionActive, let scaled {
            emit(scaled)
        }
    }

    private func handleLoopFrame(_ loopBuffer: CVPixelBuffer) {
        if let step = pendingLiveStep {
            pendingLiveTicks += 1
            let linedUp = (loopEngine?.currentStep ?? step) >= step
            if linedUp || pendingLiveTicks >= Self.smartMaxWaitTicks { beginTransitionToLive() }
        }
        if transitionActive {
            transitionProgress = min(transitionProgress + transitionIncrement, 1.0)
            let t = CGFloat(transitionProgress)
            let output: CVPixelBuffer?
            if transitionToLoop {
                output = latestLiveOutput.map { pipeline.blend(from: $0, to: loopBuffer, t: t) } ?? loopBuffer
            } else {
                output = latestLiveOutput.map { pipeline.blend(from: loopBuffer, to: $0, t: t) } ?? loopBuffer
            }
            if let output { emit(output) }
            if transitionProgress >= 1.0 { finishTransition() }
        } else if mode == .loop {
            emit(loopBuffer)
        }
    }

    // MARK: - Private

    private func beginTransitionToLive() {
        pendingLiveStep = nil
        transitionActive = true
        transitionToLoop = false
        transitionProgress = 0
    }

    private func smartStartFrame() -> Int? {
        guard let live = latestLiveOutput else { return nil }
        return loopEngine?.bestStartFrame(matching: pipeline.signature(of: live))
    }

    /// The step to begin the crossfade at, or nil to go right away.
    private func smartReturnStep() -> Int? {
        guard let live = latestLiveOutput, let engine = loopEngine else { return nil }
        let best = engine.bestUpcomingStep(matching: pipeline.signature(of: live),
                                           horizon: Self.smartHorizonSteps)
        let start = best - Self.smartLeadSteps
        return start > engine.currentStep ? start : nil
    }

    private func finishTransition() {
        transitionActive = false
        if transitionToLoop {
            setMode(.loop)
        } else {
            setMode(.live)
            loopEngine?.stop()
        }
    }

    private func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        DispatchQueue.main.async { self.onModeChange?(newMode) }
    }
}
