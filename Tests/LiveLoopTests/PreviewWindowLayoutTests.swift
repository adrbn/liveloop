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
}
