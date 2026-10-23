//
//  CameraCaptureManager.swift
//  LiveLoop
//
//  Owns the AVCaptureSession that reads the physical webcam and delivers BGRA
//  sample buffers on the shared processing queue. Frames feed both the router
//  (for the virtual-camera output) and the recorder (when capturing a clip).
//

import Foundation
import AVFoundation
import CoreMedia

final class CameraCaptureManager: NSObject {

    /// Delivered on the processing queue for every captured frame.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue: DispatchQueue
    private(set) var currentDeviceID: String?
    private let frameLock = NSLock()
    private var deliveredFrame = false
    /// Set by `start` until its queued block runs: a stop queued ahead of it
    /// (slow with Video Effects on) must not count the old session's frames.
    private var startPending = false
    /// Frames stamped before this belong to the previous session.
    private var startedAt = CMTime.zero

    /// Whether a frame has arrived since the last `start`. A cold webcam can
    /// take 10 s+ to send one (e.g. with macOS Background effects on).
    var hasDeliveredFrame: Bool {
        frameLock.withLock { !startPending && deliveredFrame }
    }

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
    }

    /// Physical cameras available for selection, excluding LiveLoop's own
    /// virtual camera so a user can never feed the output back into itself.
    static func availableCameras() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .external,
            .continuityCamera,
            .deskViewCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types,
                                                         mediaType: .video,
                                                         position: .unspecified)
        return discovery.devices.filter { $0.uniqueID != LiveLoop.deviceUID }
    }

    var isRunning: Bool { session.isRunning }

    /// Starts (or restarts) capture using the given device UID, or the system
    /// default when `nil`.
    func start(deviceID: String?) {
        frameLock.withLock { startPending = true }
        queue.async {
            self.frameLock.withLock {
                self.deliveredFrame = false
                self.startPending = false
                self.startedAt = CMClockGetTime(CMClockGetHostTimeClock())
            }
            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            guard let device = Self.resolveDevice(deviceID),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.currentDeviceID = device.uniqueID
            if self.session.canSetSessionPreset(.hd1920x1080) {
                self.session.sessionPreset = .hd1920x1080
            } else {
                self.session.sessionPreset = .high
            }
            self.session.commitConfiguration()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private static func resolveDevice(_ uid: String?) -> AVCaptureDevice? {
        if let uid, let device = AVCaptureDevice(uniqueID: uid) {
            return device
        }
        return availableCameras().first ?? AVCaptureDevice.default(for: .video)
    }
}

extension CameraCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        frameLock.withLock { if pts > startedAt { deliveredFrame = true } }
        onSampleBuffer?(sampleBuffer)
    }
}
