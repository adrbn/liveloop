//
//  ImagePipelineQualityTests.swift
//  LiveLoopTests
//
//  720p must really throw detail away (chained CoreImage transforms can
//  silently cancel a downscale out), and every frame must keep the exact size
//  the virtual camera advertises.
//

import XCTest
import CoreVideo

final class ImagePipelineQualityTests: XCTestCase {

    func testFullHDKeepsFineDetail() throws {
        let pipeline = ImagePipeline()
        let output = try XCTUnwrap(pipeline.scaledToOutput(try Self.checkerboard()))
        XCTAssertGreaterThan(Self.neighbourContrast(output), 200)
    }

    func testHDSoftensFineDetail() throws {
        let pipeline = ImagePipeline()
        pipeline.outputQuality = .hd
        let output = try XCTUnwrap(pipeline.scaledToOutput(try Self.checkerboard()))
        XCTAssertLessThan(Self.neighbourContrast(output), 100)
    }

    func testHDKeepsTheEdgesClean() throws {
        // Resampling must never pull in emptiness past the frame edge (a dark border).
        let pipeline = ImagePipeline()
        pipeline.outputQuality = .hd
        let output = try XCTUnwrap(pipeline.scaledToOutput(try Self.frame { _, _ in 255 }))
        let width = CVPixelBufferGetWidth(output), height = CVPixelBufferGetHeight(output)
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1), (width / 2, 0)] {
            XCTAssertGreaterThan(Self.green(output, x: x, y: y), 245, "pixel (\(x), \(y))")
        }
    }

    func testEveryQualityKeepsTheAdvertisedFrameSize() throws {
        for quality in OutputQuality.allCases {
            let pipeline = ImagePipeline()
            pipeline.outputQuality = quality
            let output = try XCTUnwrap(pipeline.scaledToOutput(try Self.checkerboard()))
            XCTAssertEqual(CVPixelBufferGetWidth(output), Int(LiveLoop.frameWidth), "\(quality)")
            XCTAssertEqual(CVPixelBufferGetHeight(output), Int(LiveLoop.frameHeight), "\(quality)")
        }
    }

    // MARK: - Helpers

    /// A 1-pixel black/white checkerboard at the output size: the finest
    /// detail a frame can hold.
    private static func checkerboard() throws -> CVPixelBuffer {
        try frame { x, y in (x + y).isMultiple(of: 2) ? 255 : 0 }
    }

    /// A grey frame at the output size, each pixel's level given by `level`.
    private static func frame(_ level: (Int, Int) -> UInt8) throws -> CVPixelBuffer {
        let width = Int(LiveLoop.frameWidth), height = Int(LiveLoop.frameHeight)
        var created: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &created)
        let buffer = try XCTUnwrap(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let value = level(x, y)
                let pixel = base + y * rowBytes + x * 4
                pixel[0] = value; pixel[1] = value; pixel[2] = value; pixel[3] = 255
            }
        }
        return buffer
    }

    private static func green(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let raw = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        return Int(raw.assumingMemoryBound(to: UInt8.self)[y * CVPixelBufferGetBytesPerRow(buffer) + x * 4 + 1])
    }

    /// Mean green-channel difference between horizontal neighbours in the
    /// centre of the frame: ~255 for a crisp checkerboard, near 0 once blurred.
    private static func neighbourContrast(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let raw = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let base = raw.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var total = 0, count = 0
        for y in stride(from: height / 4, to: height * 3 / 4, by: 7) {
            for x in (width / 4)..<(width * 3 / 4) {
                let left = Int(base[y * rowBytes + x * 4 + 1])
                let right = Int(base[y * rowBytes + (x + 1) * 4 + 1])
                total += abs(left - right)
                count += 1
            }
        }
        return count == 0 ? 0 : Double(total) / Double(count)
    }
}
