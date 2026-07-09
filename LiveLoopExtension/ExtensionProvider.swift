//
//  ExtensionProvider.swift
//  LiveLoopExtension
//
//  The provider owns a single virtual-camera device. That device exposes two
//  streams:
//
//    • a SOURCE stream — what conferencing apps (Zoom, Meet, …) consume, and
//    • a SINK stream   — where the LiveLoop app pushes the frames to broadcast.
//
//  The device relays every buffer it receives on the sink straight to the
//  source. All of the interesting behaviour (webcam capture, looping, lag) lives
//  in the main app; the extension stays a thin, stable pass-through so the
//  always-on system-extension process has as little to go wrong as possible.
//

import Foundation
import CoreMediaIO
import CoreVideo
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.adrbn.LiveLoop.Extension", category: "Provider")

/// FourCC `'virt'` — the transport type reported by software cameras.
private let kTransportTypeVirtual: UInt32 = 0x76_69_72_74

// MARK: - Provider

final class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ExtensionDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = ExtensionDeviceSource(localizedName: LiveLoop.cameraName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            logger.error("Failed to add device: \(error.localizedDescription, privacy: .public)")
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "LiveLoop"
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

// MARK: - Device

final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!

    private var _streamSource: ExtensionStreamSource!
    private var _streamSink: ExtensionStreamSink!

    /// Number of clients currently consuming the source stream.
    private var _streamingCounter: Int = 0
    /// Number of producers (the app) currently attached to the sink stream.
    private var _streamingSinkCounter: Int = 0

    /// Placeholder generator — emits a "open LiveLoop" card whenever the app is
    /// not actively feeding frames, so clients never see a black rectangle.
    private var _timer: DispatchSourceTimer?
    private let _timerQueue = DispatchQueue(label: "com.adrbn.LiveLoop.Extension.timer", qos: .userInteractive)
    private var _lastSinkHostTimeNs: UInt64 = 0

    private var _videoDescription: CMFormatDescription!
    private var _bufferPool: CVPixelBufferPool!
    private let _placeholder = PlaceholderRenderer()

    // Stable identifiers keep the device the same across restarts so meeting
    // apps remember it as the selected camera. Shared with the app via
    // SharedConstants so both sides agree on the exact UUIDs.
    private static let deviceUUID = UUID(uuidString: LiveLoop.deviceUID)!
    private static let sourceStreamUUID = UUID(uuidString: LiveLoop.sourceStreamUID)!
    private static let sinkStreamUUID = UUID(uuidString: LiveLoop.sinkStreamUID)!

    init(localizedName: String) {
        super.init()

        device = CMIOExtensionDevice(localizedName: localizedName,
                                     deviceID: Self.deviceUUID,
                                     legacyDeviceID: nil,
                                     source: self)

        let dims = CMVideoDimensions(width: LiveLoop.frameWidth, height: LiveLoop.frameHeight)
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: LiveLoop.pixelFormat,
                                       width: dims.width,
                                       height: dims.height,
                                       extensions: nil,
                                       formatDescriptionOut: &_videoDescription)

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: dims.width,
            kCVPixelBufferHeightKey: dims.height,
            kCVPixelBufferPixelFormatTypeKey: LiveLoop.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &_bufferPool)

        let frameDuration = CMTime(value: 1, timescale: LiveLoop.frameRate)
        let videoStreamFormat = CMIOExtensionStreamFormat(formatDescription: _videoDescription,
                                                          maxFrameDuration: frameDuration,
                                                          minFrameDuration: frameDuration,
                                                          validFrameDurations: nil)

        _streamSource = ExtensionStreamSource(localizedName: "LiveLoop.Video.Source",
                                              streamID: Self.sourceStreamUUID,
                                              streamFormat: videoStreamFormat,
                                              device: device)
        _streamSink = ExtensionStreamSink(localizedName: "LiveLoop.Video.Sink",
                                          streamID: Self.sinkStreamUUID,
                                          streamFormat: videoStreamFormat,
                                          device: device)
        do {
            try device.addStream(_streamSource.stream)
            try device.addStream(_streamSink.stream)
        } catch {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = Int(kTransportTypeVirtual)
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "LiveLoop Virtual Camera"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Source stream lifecycle (a client started/stopped consuming)

    func startStreaming() {
        guard _bufferPool != nil else { return }
        _streamingCounter += 1
        // First consumer just attached — tell the app to bring the webcam up.
        if _streamingCounter == 1 { LiveLoop.ConsumerSignal.post(active: true) }
        startPlaceholderTimer()
    }

    func stopStreaming() {
        if _streamingCounter > 1 {
            _streamingCounter -= 1
        } else {
            _streamingCounter = 0
            stopPlaceholderTimer()
            // Last consumer left — the app can put the webcam back to sleep.
            LiveLoop.ConsumerSignal.post(active: false)
        }
    }

    // MARK: Sink stream lifecycle (the app attached/detached as a producer)

    func startStreamingSink(client: CMIOExtensionClient) {
        _streamingSinkCounter += 1
        consumeBuffer(client)
    }

    func stopStreamingSink() {
        if _streamingSinkCounter > 0 { _streamingSinkCounter -= 1 }
    }

    /// Pull the next buffer the app enqueued on the sink and relay it to every
    /// consumer of the source stream, then recurse to await the next one.
    private func consumeBuffer(_ client: CMIOExtensionClient) {
        guard _streamingSinkCounter > 0 else { return }
        _streamSink.stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, _, _, error in
            guard let self else { return }
            if let sampleBuffer {
                let hostTimeNs = Self.hostTimeNanoseconds()
                self._lastSinkHostTimeNs = hostTimeNs
                if self._streamingCounter > 0 {
                    self._streamSource.stream.send(sampleBuffer,
                                                   discontinuity: [],
                                                   hostTimeInNanoseconds: hostTimeNs)
                }
                let output = CMIOExtensionScheduledOutput(sequenceNumber: sequenceNumber,
                                                          hostTimeInNanoseconds: hostTimeNs)
                self._streamSink.stream.notifyScheduledOutputChanged(output)
            }
            self.consumeBuffer(client)
        }
    }

    // MARK: Placeholder frames

    private func startPlaceholderTimer() {
        guard _timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
        let interval = 1.0 / Double(LiveLoop.frameRate)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.emitPlaceholderIfIdle() }
        timer.resume()
        _timer = timer
    }

    private func stopPlaceholderTimer() {
        _timer?.cancel()
        _timer = nil
    }

    /// Only emit a placeholder when the app has not fed a real frame recently.
    private func emitPlaceholderIfIdle() {
        let now = Self.hostTimeNanoseconds()
        let idleThresholdNs: UInt64 = 400_000_000 // 0.4 s
        if now &- _lastSinkHostTimeNs < idleThresholdNs { return }
        guard _streamingCounter > 0, let pool = _bufferPool else { return }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return }

        _placeholder.draw(into: pixelBuffer)

        guard let sampleBuffer = Self.makeSampleBuffer(from: pixelBuffer,
                                                       formatDescription: _videoDescription) else { return }
        _streamSource.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: now)
    }

    // MARK: Helpers

    static func hostTimeNanoseconds() -> UInt64 {
        UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * Double(NSEC_PER_SEC))
    }

    static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer,
                                 formatDescription: CMFormatDescription) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: LiveLoop.frameRate),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
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
        return status == noErr ? sampleBuffer : nil
    }
}
