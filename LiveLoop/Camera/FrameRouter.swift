//
//  FrameRouter.swift
//  LiveLoop
//
//  Decides which frame the virtual camera shows at any instant — the live
//  webcam or the loop — and eases every switch between them, with a short
//  crossfade or a brief freeze then a cut (see `SwitchStyle`). Everything here runs on the shared
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
    /// What viewers see right now, held still during a freeze.
    private var lastEmitted: CVPixelBuffer?

    // Switch state (advanced once per loop tick).
    private var switchStyle: SwitchStyle = .crossfade
    private var transition: SwitchTransition?
    private var transitionToLoop = false
    private var transitionTick = 0
    private var heldFrame: CVPixelBuffer?
    private var transitionActive: Bool { transition != nil }

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
    }

    var currentMode: Mode { mode }

    // MARK: - Control (called from the main thread)

    func engageLive() {
        queue.async {
            self.endTransition()
            self.pendingLiveStep = nil
            self.setMode(.live)
        }
    }

    /// `smart` (beta) starts the loop on the frame that best matches you now.
    func goToLoop(smart: Bool = false) {
        queue.async {
            guard self.loopEngine?.isLoaded == true else { return }
            self.loopEngine?.start(atFrame: smart ? self.smartStartFrame() : nil)
            self.beginTransition(toLoop: true)
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

    /// Detail kept in everything the virtual camera sends, live and loop alike.
    func setOutputQuality(_ quality: OutputQuality) {
        queue.async { self.pipeline.outputQuality = quality }
    }

    /// How every switch looks, whatever triggers it (shortcut, menu, Auto away).
    func setSwitchStyle(_ style: SwitchStyle) {
        queue.async { self.switchStyle = style }
    }

    func disengage() {
        queue.async {
            self.endTransition()
            self.pendingLiveStep = nil
            self.loopEngine?.stop()
            self.latestLiveOutput = nil
            self.lastEmitted = nil
            self.setMode(.idle)
        }
    }

    // MARK: - Frame handlers (on the processing queue)

    /// Sends a frame to the virtual camera and mirrors it to the preview.
    private func emit(_ buffer: CVPixelBuffer) {
        lastEmitted = buffer
        publisher.send(buffer)
        onOutputFrame?(buffer)
    }

    func handleLiveFrame(_ sampleBuffer: CMSampleBuffer) {
        // Idle (e.g. recording a clip with the camera off): nothing to send.
        guard mode != .idle,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
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
        if let transition {
            transitionTick += 1
            if let output = transitionOutput(transition.frame(atTick: transitionTick), loopBuffer: loopBuffer) {
                emit(output)
            }
            if transitionTick >= transition.tickCount { finishTransition() }
        } else if mode == .loop {
            emit(loopBuffer)
        }
    }

    // MARK: - Private

    private func beginTransitionToLive() {
        pendingLiveStep = nil
        beginTransition(toLoop: false)
    }

    private func beginTransition(toLoop: Bool) {
        transition = SwitchTransition(style: switchStyle, frameRate: Int(LiveLoop.frameRate))
        transitionToLoop = toLoop
        transitionTick = 0
        heldFrame = lastEmitted
    }

    private func endTransition() {
        transition = nil
        heldFrame = nil
    }

    /// The frame to send on one tick of a switch.
    private func transitionOutput(_ frame: SwitchTransition.Frame, loopBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        switch frame {
        case .hold:
            // Nothing shown yet (e.g. the very first switch): no freeze to hold.
            return heldFrame ?? (transitionToLoop ? loopBuffer : latestLiveOutput)
        case .blend(let t):
            guard let live = latestLiveOutput else { return loopBuffer }
            return transitionToLoop
                ? pipeline.blend(from: live, to: loopBuffer, t: CGFloat(t))
                : pipeline.blend(from: loopBuffer, to: live, t: CGFloat(t))
        }
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
        endTransition()
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
