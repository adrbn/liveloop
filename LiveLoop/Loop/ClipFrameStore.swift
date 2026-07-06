//
//  ClipFrameStore.swift
//  LiveLoop
//
//  An in-memory, random-access representation of a clip's frames. Frames are
//  kept as JPEG data (a few MB for a whole clip instead of gigabytes of raw
//  BGRA) and decoded on demand — which is exactly what ping-pong playback needs,
//  since it jumps both forward and backward through the frames.
//

import Foundation
import AVFoundation
import CoreVideo

struct ClipFrameStore {
    /// JPEG-encoded frames in capture order.
    let frames: [Data]
    /// Nominal playback rate the clip was captured at.
    let fps: Double

    var count: Int { frames.count }
    var isEmpty: Bool { frames.isEmpty }
}

enum ClipFrameLoader {

    /// Decodes every frame of a clip into JPEG data. Runs off the main thread.
    static func load(url: URL, pipeline: ImagePipeline) async -> ClipFrameStore? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        let nominalFrameRate = (try? await track.load(.nominalFrameRate)) ?? Float(LiveLoop.frameRate)

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else { return nil }
        reader.add(trackOutput)
        guard reader.startReading() else { return nil }

        var frames: [Data] = []
        while reader.status == .reading, let sample = trackOutput.copyNextSampleBuffer() {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sample),
               let jpeg = pipeline.jpeg(from: pixelBuffer) {
                frames.append(jpeg)
            }
        }

        guard reader.status == .completed || !frames.isEmpty else { return nil }
        let fps = nominalFrameRate > 0 ? Double(nominalFrameRate) : Double(LiveLoop.frameRate)
        return ClipFrameStore(frames: frames, fps: fps)
    }
}
