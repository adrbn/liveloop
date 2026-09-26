//
//  PreviewContentTests.swift
//  LiveLoopTests
//
//  Recording works with the virtual camera off: the panel must show your
//  webcam while you record.
//

import XCTest

final class PreviewContentTests: XCTestCase {

    func testCameraOnShowsWhatViewersSee() {
        for recording in [false, true] {
            for hasClip in [false, true] {
                XCTAssertEqual(PreviewContent.resolve(engaged: true, recording: recording, hasClip: hasClip),
                               .output)
            }
        }
    }

    func testRecordingWithTheCameraOffShowsYourWebcam() {
        XCTAssertEqual(PreviewContent.resolve(engaged: false, recording: true, hasClip: false), .selfView)
        XCTAssertEqual(PreviewContent.resolve(engaged: false, recording: true, hasClip: true), .selfView)
    }

    func testIdleWithAClipShowsTheLoopReady() {
        XCTAssertEqual(PreviewContent.resolve(engaged: false, recording: false, hasClip: true), .loopReady)
    }

    func testIdleWithoutAClipAsksForARecording() {
        XCTAssertEqual(PreviewContent.resolve(engaged: false, recording: false, hasClip: false), .noClip)
    }
}
