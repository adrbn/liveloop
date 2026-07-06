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
        queue.async {
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
        onSampleBuffer?(sampleBuffer)
    }
}
