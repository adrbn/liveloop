//
//  WebcamClaimsTests.swift
//  LiveLoopTests
//
//  The webcam is shared by the virtual camera and clip recordings. It must
//  start exactly once, never restart under a recording, and go off as soon as
//  nobody needs it (no camera light left on after a clip).
//

import XCTest

final class WebcamClaimsTests: XCTestCase {

    func testTheFirstClaimTurnsTheWebcamOn() {
        var claims = WebcamClaims()
        XCTAssertTrue(claims.claim(.clip))
        XCTAssertTrue(claims.isOn)
    }

    func testASecondOwnerNeverRestartsIt() {
        // e.g. the shortcut or a meeting app engages mid-recording.
        var claims = WebcamClaims()
        _ = claims.claim(.clip)
        XCTAssertFalse(claims.claim(.virtualCamera))
    }

    func testClaimingTwiceIsHarmless() {
        var claims = WebcamClaims()
        _ = claims.claim(.virtualCamera)
        XCTAssertFalse(claims.claim(.virtualCamera))
        XCTAssertTrue(claims.release(.virtualCamera))
    }

    func testItStaysOnWhileSomeoneStillNeedsIt() {
        // Stopping the virtual camera mid-recording keeps the webcam for the clip.
        var claims = WebcamClaims()
        _ = claims.claim(.virtualCamera)
        _ = claims.claim(.clip)
        XCTAssertFalse(claims.release(.virtualCamera))
        XCTAssertTrue(claims.isOn)
    }

    func testTheLastReleaseTurnsItOff() {
        var claims = WebcamClaims()
        _ = claims.claim(.virtualCamera)
        _ = claims.claim(.clip)
        _ = claims.release(.virtualCamera)
        XCTAssertTrue(claims.release(.clip))
        XCTAssertFalse(claims.isOn)
    }

    func testReleasingWhatWasNeverClaimedDoesNothing() {
        var claims = WebcamClaims()
        XCTAssertFalse(claims.release(.clip))
        _ = claims.claim(.virtualCamera)
        XCTAssertFalse(claims.release(.clip))
        XCTAssertTrue(claims.isOn)
    }
}
