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
            self.setMode(.live)
        }
    }

    func goToLoop() {
        queue.async {
            guard self.loopEngine?.isLoaded == true else { return }
            self.loopEngine?.start()
            self.transitionActive = true
            self.transitionToLoop = true
            self.transitionProgress = 0
        }
    }

    func goToLive() {
        queue.async {
            guard self.mode == .loop || (self.transitionActive && self.transitionToLoop) else { return }
            self.transitionActive = true
            self.transitionToLoop = false
            self.transitionProgress = 0
        }
    }

    func disengage() {
        queue.async {
            self.transitionActive = false
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
