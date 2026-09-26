//
//  OutputQualityTests.swift
//  LiveLoopTests
//
//  The 720p option softens the picture but must never change the frame size
//  the virtual camera advertises, and a bad stored value must fall back safely.
//

import XCTest

final class OutputQualityTests: XCTestCase {

    func testFullHDKeepsEveryPixel() {
        XCTAssertEqual(OutputQuality.fullHD.detailScale, 1)
    }

    func testHDRendersAt720p() {
        let size = OutputQuality.hd.renderedSize
        XCTAssertEqual(size.width, 1280, accuracy: 0.001)
        XCTAssertEqual(size.height, 720, accuracy: 0.001)
    }

    func testEveryQualityKeepsTheOutputAspectRatio() {
        let outputAspect = Double(LiveLoop.frameWidth) / Double(LiveLoop.frameHeight)
        for quality in OutputQuality.allCases {
            let size = quality.renderedSize
            XCTAssertEqual(size.width / size.height, outputAspect, accuracy: 0.001, "\(quality)")
        }
    }

    func testMissingOrUnknownStoredValueFallsBackToFullHD() {
        XCTAssertEqual(OutputQuality(storedValue: nil), .fullHD)
        XCTAssertEqual(OutputQuality(storedValue: "4k"), .fullHD)
    }

    func testStoredValueRoundTrips() {
        for quality in OutputQuality.allCases {
            XCTAssertEqual(OutputQuality(storedValue: quality.rawValue), quality)
        }
    }
}
