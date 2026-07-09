//
//  CameraPreview.swift
//  LiveLoop
//
//  In-app preview of exactly what the virtual camera is broadcasting (live,
//  loop, or the crossfade between them) — the "viewers see your loop" mirror,
//  driven by the same frames the router sends to the extension.
//

import SwiftUI
import AVFoundation
import CoreMedia
import CoreVideo

/// Displays output frames efficiently via an AVSampleBufferDisplayLayer.
final class PreviewRenderer {

    let layer = AVSampleBufferDisplayLayer()

    init() {
        layer.videoGravity = .resizeAspectFill
    }

    /// Enqueue one output frame for immediate display. Call on the main thread.
    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: .invalid,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                           imageBuffer: pixelBuffer,
                                           dataReady: true,
                                           makeDataReadyCallback: nil,
                                           refcon: nil,
                                           formatDescription: formatDescription,
                                           sampleTiming: &timing,
                                           sampleBufferOut: &sampleBuffer)
        guard let sampleBuffer else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        if layer.status == .failed { layer.flush() }
        layer.enqueue(sampleBuffer)
    }

    func clear() {
        layer.flushAndRemoveImage()
    }
}

/// SwiftUI host for the preview layer.
struct CameraPreview: NSViewRepresentable {
    let renderer: PreviewRenderer

    func makeNSView(context: Context) -> PreviewHostView {
        PreviewHostView(displayLayer: renderer.layer)
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {}
}

final class PreviewHostView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }
}
