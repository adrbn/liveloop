//
//  SystemAudioTap.swift
//  LiveLoop
//
//  Beta (name alert) — hears the meeting itself, even through headphones, by
//  tapping the Mac's audio output with a Core Audio process tap (macOS 14.2+).
//  The tap is private and doesn't mute anything; macOS asks once for
//  permission to record system audio. Torn down as soon as the loop ends.
//

import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

@available(macOS 14.2, *)
final class SystemAudioTap: NameAlertAudioSource {

    private let queue = DispatchQueue(label: "com.adrbn.LiveLoop.audiotap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        do {
            try startTap(onBuffer: onBuffer)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: - Private

    private func startTap(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "LiveLoop Name Alert"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        try check(AudioHardwareCreateProcessTap(description, &tapID), "create tap")
        var streamDescription = try tapFormat()
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw AudioSourceError.coreAudio("read format", -1)
        }

        let outputUID = try defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LiveLoop Name Alert",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create device")

        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, _, _ in
            // The buffer only lives for this callback; the resampler copies it.
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            onBuffer(buffer)
        }, "create IO proc")
        try check(AudioDeviceStart(aggregateID, ioProcID), "start")
    }

    private func tapFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "read format")
        return format
    }

    private func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID),
                  "find output device")

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        try check(withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
        }, "read output device")
        return uid as String
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw AudioSourceError.coreAudio(step, status) }
    }
}
