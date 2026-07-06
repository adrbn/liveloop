//
//  PlaceholderRenderer.swift
//  LiveLoopExtension
//
//  Draws the "open LiveLoop" card the virtual camera shows whenever the app is
//  not actively feeding frames. Kept to CoreGraphics + CoreText so it works
//  inside the sandboxed extension without AppKit / window-server access.
//

import Foundation
import CoreVideo
import CoreGraphics
import CoreText

final class PlaceholderRenderer {

    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    /// Renders the placeholder card directly into a BGRA pixel buffer.
    func draw(into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: base,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo) else { return }

        let w = CGFloat(width)
        let h = CGFloat(height)

        // Background — LiveLoop's near-black navy.
        ctx.setFillColor(red: 0.055, green: 0.067, blue: 0.098, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Accent ring above the wordmark.
        let ringR = h * 0.055
        let ringCenter = CGPoint(x: w / 2, y: h * 0.60)
        ctx.setLineWidth(h * 0.010)
        ctx.setStrokeColor(red: 0.36, green: 0.55, blue: 1.0, alpha: 1)
        ctx.strokeEllipse(in: CGRect(x: ringCenter.x - ringR,
                                     y: ringCenter.y - ringR,
                                     width: ringR * 2,
                                     height: ringR * 2))
        ctx.setFillColor(red: 0.36, green: 0.55, blue: 1.0, alpha: 1)
        let dotR = h * 0.016
        ctx.fillEllipse(in: CGRect(x: ringCenter.x - dotR,
                                   y: ringCenter.y - dotR,
                                   width: dotR * 2,
                                   height: dotR * 2))

        drawCentered("LiveLoop",
                     fontSize: h * 0.085,
                     baselineY: h * 0.44,
                     color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                     bold: true, ctx: ctx, width: w)
        drawCentered("Open the app to go live",
                     fontSize: h * 0.034,
                     baselineY: h * 0.36,
                     color: CGColor(red: 0.58, green: 0.64, blue: 0.74, alpha: 1),
                     bold: false, ctx: ctx, width: w)
    }

    private func drawCentered(_ string: String,
                              fontSize: CGFloat,
                              baselineY: CGFloat,
                              color: CGColor,
                              bold: Bool,
                              ctx: CGContext,
                              width: CGFloat) {
        let fontName = bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: (width - textWidth) / 2, y: baselineY)
        CTLineDraw(line, ctx)
    }
}
