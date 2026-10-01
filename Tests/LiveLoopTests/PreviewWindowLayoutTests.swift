//
//  PreviewWindowLayoutTests.swift
//  LiveLoopTests
//
//  The big preview shows the loop and your real camera side by side, or one
//  over the other to line yourself up. Overlay must let both show through.
//

import XCTest

final class PreviewWindowLayoutTests: XCTestCase {

    func testSideBySideShowsYourCameraUntouched() {
        XCTAssertEqual(PreviewWindowLayout.sideBySide.liveOpacity, 1)
    }

    func testOverlayLetsTheLoopShowThroughYourCamera() {
        let opacity = PreviewWindowLayout.overlay.liveOpacity
        XCTAssertGreaterThan(opacity, 0.2)
        XCTAssertLessThan(opacity, 0.8)
    }

    func testMissingOrUnknownStoredLayoutFallsBackToSideBySide() {
        XCTAssertEqual(PreviewWindowLayout(storedValue: nil), .sideBySide)
        XCTAssertEqual(PreviewWindowLayout(storedValue: "grid"), .sideBySide)
    }

    func testStoredLayoutRoundTrips() {
        for layout in PreviewWindowLayout.allCases {
            XCTAssertEqual(PreviewWindowLayout(storedValue: layout.rawValue), layout)
        }
    }

    func testSideBySideFitsTwoPicturesWithNoBars() {
        let size = PreviewWindowLayout.sideBySide.contentSize(paneHeight: 180, titleBar: 32, gap: 6)
        XCTAssertEqual(size.width, 2 * 320 + 3 * 6, accuracy: 0.001)
        XCTAssertEqual(size.height, 32 + 180 + 6, accuracy: 0.001)
    }

    func testOverlayFitsOnePictureWithNoBars() {
        let size = PreviewWindowLayout.overlay.contentSize(paneHeight: 180, titleBar: 32, gap: 6)
        XCTAssertEqual(size.width, 320 + 2 * 6, accuracy: 0.001)
        XCTAssertEqual(size.height, 32 + 180 + 6, accuracy: 0.001)
    }

    func testPaneHeightIsReadBackFromAWindowHeight() {
        XCTAssertEqual(PreviewWindowLayout.paneHeight(contentHeight: 218, titleBar: 32, gap: 6), 180, accuracy: 0.001)
    }
}
