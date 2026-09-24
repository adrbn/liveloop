//
//  LiveFrameTap.swift
//  LiveLoop
//
//  A switchable side-channel off the live camera feed. With no consumer (every
//  beta feature off) offering a frame does nothing; auto away plugs its face
//  sampler in here. Called on the processing queue, so it must stay cheap.
//

import Foundation
import CoreVideo

final class LiveFrameTap: @unchecked Sendable {

    private let lock = NSLock()
    private var consumer: ((CVPixelBuffer) -> Void)?

    func setConsumer(_ consumer: ((CVPixelBuffer) -> Void)?) {
        lock.withLock { self.consumer = consumer }
    }

    func offer(_ buffer: CVPixelBuffer) {
        let consumer = lock.withLock { self.consumer }
        consumer?(buffer)
    }
}
