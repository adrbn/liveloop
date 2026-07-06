//
//  ClipRecorder.swift
//  LiveLoop
//
//  Records a short clip by encoding the webcam sample buffers straight to an
//  H.264 .mov with AVAssetWriter. Driven entirely from the processing queue:
//  `append` is fed each captured frame, and recording ends either on `stop()`
//  or when the safety `maxDuration` is reached.
//

import Foundation
import AVFoundation

final class ClipRecorder {

    private(set) var isRecording = false

    private let queue: DispatchQueue
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startPTS: CMTime?
    private var outputURL: URL?
    private var maxDuration: Double = 60
    private var onFinished: ((URL?, Double) -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Begins recording. `onFinished` fires (on the main queue) with the temp
    /// file URL and its duration, or `nil` on failure.
    func start(maxDuration: Double, onFinished: @escaping (URL?, Double) -> Void) {
        queue.async {
            guard !self.isRecording else { return }
            self.maxDuration = maxDuration
            self.onFinished = onFinished
            self.writer = nil
            self.input = nil
            self.startPTS = nil
            self.outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("liveloop-\(UUID().uuidString).mov")
            self.isRecording = true
        }
    }

    /// Feed each captured frame here (already on the processing queue).
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        if writer == nil { setup(with: sampleBuffer) }
        guard let writer, let input, writer.status == .writing else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if startPTS == nil {
            startPTS = pts
            writer.startSession(atSourceTime: pts)
        }
        lastPTS = pts
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
        if let start = startPTS, CMTimeGetSeconds(CMTimeSubtract(pts, start)) >= maxDuration {
            finish()
        }
    }

    func stop() {
        queue.async { self.finish() }
    }

    // MARK: - Private

    private func setup(with sampleBuffer: CMSampleBuffer) {
        guard let url = outputURL,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(format)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dims.width),
            AVVideoHeightKey: Int(dims.height),
        ]
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) { writer.add(input) }
        guard writer.startWriting() else { return }
        self.writer = writer
        self.input = input
    }

    private func finish() {
        guard isRecording else { return }
        isRecording = false

        guard let writer, let input, let start = startPTS else {
            deliver(nil, 0)
            return
        }
        let endPTS = writer.status == .writing ? currentEndTime() : start
        let duration = max(0, CMTimeGetSeconds(CMTimeSubtract(endPTS, start)))
        input.markAsFinished()
        let url = outputURL
        writer.finishWriting { [weak self] in
            let success = writer.status == .completed
            self?.deliver(success ? url : nil, duration)
        }
    }

    private var lastPTS: CMTime = .zero
    private func currentEndTime() -> CMTime {
        lastPTS == .zero ? (startPTS ?? .zero) : lastPTS
    }

    private func deliver(_ url: URL?, _ duration: Double) {
        let callback = onFinished
        onFinished = nil
        writer = nil
        input = nil
        DispatchQueue.main.async { callback?(url, duration) }
    }
}
