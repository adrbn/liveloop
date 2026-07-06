//
//  ExtensionStreams.swift
//  LiveLoopExtension
//
//  The two stream sources backing the virtual-camera device:
//
//    • ExtensionStreamSource — the `.source` stream consumed by meeting apps.
//    • ExtensionStreamSink   — the `.sink` stream the LiveLoop app produces into.
//
//  Both simply forward their start/stop lifecycle to the owning device source,
//  which performs the actual relay.
//

import Foundation
import CoreMediaIO
import CoreMedia

// MARK: - Source stream (extension → meeting apps)

final class ExtensionStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    let device: CMIOExtensionDevice
    private let _streamFormat: CMIOExtensionStreamFormat

    init(localizedName: String,
         streamID: UUID,
         streamFormat: CMIOExtensionStreamFormat,
         device: CMIOExtensionDevice) {
        self.device = device
        self._streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(localizedName: localizedName,
                                          streamID: streamID,
                                          direction: .source,
                                          clockType: .hostTime,
                                          source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [_streamFormat] }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: LiveLoop.frameRate)
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            self.activeFormatIndex = activeFormatIndex
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws {
        guard let deviceSource = device.source as? ExtensionDeviceSource else {
            throw NSError(domain: "LiveLoop", code: -1)
        }
        deviceSource.startStreaming()
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? ExtensionDeviceSource else {
            throw NSError(domain: "LiveLoop", code: -1)
        }
        deviceSource.stopStreaming()
    }
}

// MARK: - Sink stream (LiveLoop app → extension)

final class ExtensionStreamSink: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    let device: CMIOExtensionDevice
    private let _streamFormat: CMIOExtensionStreamFormat

    /// The producer client (the LiveLoop app). Captured when the sink is
    /// authorised, then used to pull enqueued buffers once streaming starts.
    private var client: CMIOExtensionClient?

    init(localizedName: String,
         streamID: UUID,
         streamFormat: CMIOExtensionStreamFormat,
         device: CMIOExtensionDevice) {
        self.device = device
        self._streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(localizedName: localizedName,
                                          streamID: streamID,
                                          direction: .sink,
                                          clockType: .hostTime,
                                          source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [_streamFormat] }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = 3
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = 1
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            self.activeFormatIndex = activeFormatIndex
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let deviceSource = device.source as? ExtensionDeviceSource,
              let client else {
            throw NSError(domain: "LiveLoop", code: -1)
        }
        deviceSource.startStreamingSink(client: client)
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? ExtensionDeviceSource else {
            throw NSError(domain: "LiveLoop", code: -1)
        }
        deviceSource.stopStreamingSink()
    }
}
