//
//  ImagePipeline.swift
//  LiveLoop
//
//  Single owner of all pixel work: a Metal-backed CoreImage context plus a
//  pixel-buffer pool that produces IOSurface-backed BGRA frames at the exact
//  geometry the virtual camera advertises. Every frame the app sends to the
//  extension — live, looped, or a crossfade — passes through here so the output
//  is always uniform.
//

import Foundation
import CoreImage
import CoreVideo
import Metal

final class ImagePipeline {

    private let context: CIContext
    private let pool: CVPixelBufferPool
    private let outputWidth = Int(LiveLoop.frameWidth)
    private let outputHeight = Int(LiveLoop.frameHeight)

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }

        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight,
            kCVPixelBufferPixelFormatTypeKey as String: LiveLoop.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var createdPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &createdPool)
        pool = createdPool!
    }

    // MARK: - Output buffers

    private func dequeue() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess else {
            return nil
        }
        return buffer
    }

    // MARK: - Public operations

    /// Scales/crops any pixel buffer to fill the output geometry (aspect fill,
    /// centre crop). Returns a fresh output buffer.
    func scaledToOutput(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        render(CIImage(cvPixelBuffer: source))
    }

    /// Decodes a JPEG frame and scales it to the output geometry.
    func decodeToOutput(_ jpeg: Data) -> CVPixelBuffer? {
        guard let image = CIImage(data: jpeg) else { return nil }
        return render(image)
    }

    /// Crossfades between two already-output-sized buffers. `t` is `0` (all
    /// `from`) to `1` (all `to`).
    func blend(from: CVPixelBuffer, to: CVPixelBuffer, t: CGFloat) -> CVPixelBuffer? {
        let clamped = min(max(t, 0), 1)
        let fromImage = CIImage(cvPixelBuffer: from)
        let toImage = CIImage(cvPixelBuffer: to).applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: clamped),
        ])
        let composited = toImage.composited(over: fromImage)
        guard let output = dequeue() else { return nil }
        context.render(composited, to: output)
        return output
    }

    /// Encodes a pixel buffer as JPEG (used when extracting clip frames).
    func jpeg(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.85) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return context.jpegRepresentation(of: image,
                                           colorSpace: colorSpace,
                                           options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }

    // MARK: - Beta effects

    /// Beta (connection profiles): re-renders an output buffer as if it came
    /// through a starved video codec — soft when mildly degraded, blocky when
    /// badly degraded. `quality` is `1` (untouched) down towards `0`.
    func degraded(_ buffer: CVPixelBuffer, quality: Double) -> CVPixelBuffer? {
        guard quality < 0.999 else { return buffer }
        let q = min(max(quality, 0.01), 1)
        let scale = CGFloat(max(1.0 / 20, q * q))
        let source = CIImage(cvPixelBuffer: buffer)
        let small = source.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1,
        ])
        guard small.extent.width > 0, small.extent.height > 0 else { return buffer }
        let clamped = small.clampedToExtent()
        let upscaleSource = q < 0.35 ? clamped.samplingNearest() : clamped
        let restored = upscaleSource
            .transformed(by: CGAffineTransform(scaleX: source.extent.width / small.extent.width,
                                               y: source.extent.height / small.extent.height))
            .cropped(to: source.extent)
        guard let output = dequeue() else { return nil }
        context.render(restored, to: output)
        return output
    }

    /// Beta (smart switch): a tiny grayscale thumbnail of the frame, cropped
    /// the same way as the output, used to compare poses.
    func signature(of buffer: CVPixelBuffer) -> [UInt8] {
        let width = PoseMatcher.signatureWidth
        let height = PoseMatcher.signatureHeight
        let image = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return [] }

        let scale = max(CGFloat(width) / extent.width, CGFloat(height) / extent.height)
        let small = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1,
        ])
        let dx = (small.extent.width - CGFloat(width)) / 2
        let dy = (small.extent.height - CGFloat(height)) / 2
        let luma = small
            .transformed(by: CGAffineTransform(translationX: -small.extent.minX - dx,
                                               y: -small.extent.minY - dy))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            ])

        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(luma, toBitmap: base, rowBytes: width,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height),
                           format: .R8, colorSpace: nil)
        }
        return pixels
    }

    // MARK: - Private

    /// Renders a CIImage into a fresh output buffer using aspect-fill geometry.
    private func render(_ image: CIImage) -> CVPixelBuffer? {
        guard let output = dequeue() else { return nil }
        let positioned = aspectFill(image)
        context.render(positioned, to: output)
        return output
    }

    /// Scales `image` to cover the output rect, then translates so the centre
    /// crop maps onto the buffer origin.
    private func aspectFill(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(CGFloat(outputWidth) / extent.width,
                        CGFloat(outputHeight) / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (scaled.extent.width - CGFloat(outputWidth)) / 2
        let dy = (scaled.extent.height - CGFloat(outputHeight)) / 2
        return scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.minX - dx,
                                                        y: -scaled.extent.minY - dy))
    }
}
