//
//  FaceSampler.swift
//  LiveLoop
//
//  Beta — answers "is someone at the desk?" a few times per second using
//  on-device Vision (a face, or failing that an upper body). Frames arrive on
//  the processing queue; analysis runs on its own low-priority queue and at
//  most one frame is in flight, so it never slows the video down.
//

import Foundation
import CoreVideo
import Vision
import os.log

private let logger = Logger(subsystem: "com.adrbn.LiveLoop", category: "FaceSampler")

final class FaceSampler: @unchecked Sendable {

    /// ~2.5 checks per second is plenty to notice someone leaving.
    static let interval: TimeInterval = 0.4

    private let queue = DispatchQueue(label: "com.adrbn.LiveLoop.presence", qos: .utility)
    private let lock = NSLock()
    private var lastSampleAt: TimeInterval = 0
    private var busy = false
    private let onResult: @Sendable (_ present: Bool, _ at: TimeInterval) -> Void

    init(onResult: @escaping @Sendable (_ present: Bool, _ at: TimeInterval) -> Void) {
        self.onResult = onResult
    }

    /// Cheap to call for every frame: most are skipped.
    func offer(_ buffer: CVPixelBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        let accepted: Bool = lock.withLock {
            guard !busy, now - lastSampleAt >= Self.interval else { return false }
            busy = true
            lastSampleAt = now
            return true
        }
        guard accepted else { return }
        queue.async { [self] in
            let present = Self.someoneIsThere(in: buffer)
            lock.withLock { busy = false }
            onResult(present, now)
        }
    }

    private static func someoneIsThere(in buffer: CVPixelBuffer) -> Bool {
        let faces = VNDetectFaceRectanglesRequest()
        let bodies = VNDetectHumanRectanglesRequest()
        bodies.upperBodyOnly = true
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([faces, bodies])
        } catch {
            // Never loop because detection failed: treat errors as "still here".
            logger.error("Presence detection failed: \(error.localizedDescription, privacy: .public)")
            return true
        }
        let face = !(faces.results ?? []).isEmpty
        let body = (bodies.results ?? []).contains { $0.confidence >= 0.5 }
        return face || body
    }
}
