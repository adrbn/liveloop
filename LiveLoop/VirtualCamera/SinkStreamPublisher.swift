//
//  SinkStreamPublisher.swift
//  LiveLoop
//
//  Pushes CVPixelBuffers from the app into the camera extension's *sink* stream
//  using the CoreMediaIO C API. The extension relays whatever lands here to its
//  source stream, which is what Zoom / Meet / Teams actually display.
//
//  Discovery is by the stable device UID (SharedConstants.deviceUID) so a user
//  renaming the camera never breaks the connection.
//

import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.adrbn.LiveLoop", category: "SinkPublisher")

/// Result of attempting to connect to the extension's sink stream.
enum SinkConnectionState: Equatable {
    case disconnected
    case connected
    case deviceNotFound
}

final class SinkStreamPublisher {

    private(set) var state: SinkConnectionState = .disconnected

    private var deviceID: CMIODeviceID = 0
    private var sinkStreamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private var formatDescription: CMFormatDescription?
    private var frameCount: UInt64 = 0

    /// Attempts to locate the LiveLoop virtual camera and open its sink stream.
    /// Returns the resulting state; call again after activating the extension.
    @discardableResult
    func connect() -> SinkConnectionState {
        guard let device = Self.findDevice(uid: LiveLoop.deviceUID) else {
            state = .deviceNotFound
            return state
        }
        deviceID = device

        guard let sink = Self.findSinkStream(device: device) else {
            state = .deviceNotFound
            return state
        }
        sinkStreamID = sink

        // Grab the queue we enqueue buffers into. The altered-proc is required
        // but we drive enqueueing ourselves, so it stays a no-op.
        var queueRef: Unmanaged<CMSimpleQueue>?
        let status = CMIOStreamCopyBufferQueue(sinkStreamID, { _, _, _ in }, nil, &queueRef)
        guard status == noErr, let queueRef else {
            logger.error("CMIOStreamCopyBufferQueue failed: \(status)")
            state = .disconnected
            return state
        }
        queue = queueRef.takeRetainedValue()

        let startStatus = CMIODeviceStartStream(deviceID, sinkStreamID)
        guard startStatus == noErr else {
            logger.error("CMIODeviceStartStream failed: \(startStatus)")
            state = .disconnected
            return state
        }

        state = .connected
        logger.info("Connected to LiveLoop sink stream.")
        return state
    }

    func disconnect() {
        guard state == .connected else { return }
        CMIODeviceStopStream(deviceID, sinkStreamID)
        queue = nil
        state = .disconnected
    }

    /// Cheap check for whether the LiveLoop virtual camera is currently
    /// installed and visible to the system, without opening a stream.
    static func deviceIsAvailable() -> Bool {
        findDevice(uid: LiveLoop.deviceUID) != nil
    }

    /// Enqueues one frame for the extension to broadcast. Silently drops the
    /// frame if the sink queue is full (the consumer is momentarily behind) so
    /// we never block the capture pipeline.
    func send(_ pixelBuffer: CVPixelBuffer) {
        guard state == .connected, let queue else { return }

        // A full queue means the extension hasn't drained yet — skip this frame.
        if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) { return }

        if formatDescription == nil ||
            !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
            var desc: CMFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                         imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &desc)
            formatDescription = desc
        }
        guard let formatDescription else { return }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: LiveLoop.frameRate),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)

        guard status == noErr, let sampleBuffer else { return }

        // The queue takes ownership of a retained reference; the extension
        // releases it after consuming.
        CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sampleBuffer).toOpaque())
        frameCount &+= 1
    }

    // MARK: - Device / stream discovery

    private static func findDevice(uid: String) -> CMIODeviceID? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                            &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return nil
        }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                        &address, 0, nil, dataSize, &dataUsed, &devices) == noErr else {
            return nil
        }

        for device in devices {
            if let deviceUID = stringProperty(object: device, selector: Int(kCMIODevicePropertyDeviceUID)),
               deviceUID.caseInsensitiveCompare(uid) == .orderedSame {
                return device
            }
        }
        return nil
    }

    private static func findSinkStream(device: CMIODeviceID) -> CMIOStreamID? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return nil
        }
        let count = Int(dataSize) / MemoryLayout<CMIOStreamID>.size
        var streams = [CMIOStreamID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, dataSize, &dataUsed, &streams) == noErr,
              !streams.isEmpty else {
            return nil
        }

        // The sink is the stream the host writes *into* the device. CMIO reports
        // that as direction == 1 (a normal camera source stream is 0). Fall back
        // to the last stream, since the extension always adds the source first
        // and the sink second.
        for stream in streams {
            if let direction = uint32Property(object: stream, selector: Int(kCMIOStreamPropertyDirection)),
               direction == 1 {
                return stream
            }
        }
        return streams.last
    }

    private static func uint32Property(object: CMIOObjectID, selector: Int) -> UInt32? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize) == noErr,
              dataSize == UInt32(MemoryLayout<UInt32>.size) else {
            return nil
        }
        var value: UInt32 = 0
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, dataSize, &dataUsed, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func stringProperty(object: CMIOObjectID, selector: Int) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return nil
        }
        var cfString: CFString?
        var dataUsed: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &cfString) { ptr -> OSStatus in
            CMIOObjectGetPropertyData(object, &address, 0, nil, dataSize, &dataUsed, ptr)
        }
        guard status == noErr else { return nil }
        return cfString as String?
    }
}
