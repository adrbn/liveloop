//
//  AudioSources.swift
//  LiveLoop
//
//  Beta (name alert) — where the listener gets its audio from: the meeting's
//  sound (a Core Audio system tap, macOS 14.2+) or the microphone. Audio is
//  only ever handed to the on-device speech recognizer; nothing is recorded.
//

import Foundation
import AVFoundation

protocol NameAlertAudioSource: AnyObject {
    /// Starts delivering buffers (on an arbitrary thread) until `stop()`.
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

enum AudioSourceError: LocalizedError {
    case needsNewerMacOS
    case noInputDevice
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .needsNewerMacOS:
            return "Listening to meeting audio needs macOS 14.2 or later. Choose Microphone in Settings ▸ Beta."
        case .noInputDevice:
            return "No microphone found."
        case .coreAudio(let step, let status):
            return "Couldn't listen to meeting audio (\(step), error \(status))."
        }
    }
}

enum NameAlertAudio {
    static func makeSource(_ kind: NameAlertSource) throws -> NameAlertAudioSource {
        switch kind {
        case .microphone:
            return MicrophoneSource()
        case .meetingAudio:
            guard #available(macOS 14.2, *) else { throw AudioSourceError.needsNewerMacOS }
            return SystemAudioTap()
        }
    }
}

/// The built-in (or selected) microphone via AVAudioEngine.
final class MicrophoneSource: NameAlertAudioSource {

    private let engine = AVAudioEngine()

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioSourceError.noInputDevice }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in onBuffer(buffer) }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// Converts whatever the source delivers into the 16 kHz mono float buffers
/// speech recognition works best with. Used from a single audio thread.
final class MonoResampler {

    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                             channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converter?.downmix = true
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
