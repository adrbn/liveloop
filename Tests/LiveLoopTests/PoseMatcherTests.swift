//
//  PoseMatcherTests.swift
//  LiveLoopTests
//
//  Beta — smart switch: start the loop on the frame that looks most like you
//  right now, and return to live when the loop lines up with you again.
//

import XCTest

final class PoseMatcherTests: XCTestCase {

    /// A tiny synthetic "frame": a bright square at column `x` on a dark field.
    private func frame(x: Int, brightness: UInt8 = 200, background: UInt8 = 20) -> [UInt8] {
        var pixels = [UInt8](repeating: background, count: PoseMatcher.signatureLength)
        for row in 4..<12 {
            for col in x..<(x + 6) where col < PoseMatcher.signatureWidth {
                pixels[row * PoseMatcher.signatureWidth + col] = brightness
            }
        }
        return pixels
    }

    func testIdenticalFramesHaveZeroDistance() {
        XCTAssertEqual(PoseMatcher.distance(frame(x: 5), frame(x: 5)), 0, accuracy: 0.0001)
    }

    func testCloserPosesAreCloser() {
        let target = frame(x: 10)
        XCTAssertLessThan(PoseMatcher.distance(target, frame(x: 11)),
                          PoseMatcher.distance(target, frame(x: 20)))
    }

    func testIgnoresOverallBrightnessShifts() {
        // Auto-exposure brightening the whole frame is not a different pose.
        let dim = frame(x: 10, brightness: 180, background: 10)
        let bright = frame(x: 10, brightness: 220, background: 50)
        let moved = frame(x: 18)
        XCTAssertLessThan(PoseMatcher.distance(dim, bright), PoseMatcher.distance(dim, moved))
    }

    func testMismatchedOrEmptySignaturesNeverMatch() {
        XCTAssertEqual(PoseMatcher.distance([], frame(x: 1)), .infinity)
        XCTAssertEqual(PoseMatcher.distance([1, 2, 3], frame(x: 1)), .infinity)
    }

    func testBestIndexFindsTheClosestFrame() {
        let clip = (0..<20).map { frame(x: $0) }
        XCTAssertEqual(PoseMatcher.bestIndex(in: clip, matching: frame(x: 13)), 13)
    }

    func testBestIndexIsNilForAnEmptyClip() {
        XCTAssertNil(PoseMatcher.bestIndex(in: [], matching: frame(x: 3)))
    }

    func testBestUpcomingStepLooksAheadThroughThePingPong() {
        // 10 frames; at step 8 we're moving forward (index 8). The best match for
        // index 5 within the horizon is reached on the way back: steps 9 (idx 9),
        // 10 (idx 8), 11 (7), 12 (6), 13 (5).
        let clip = (0..<10).map { frame(x: $0 * 2) }
        let seq = PingPongSequencer(frameCount: 10)
        let step = PoseMatcher.bestUpcomingStep(from: 8, horizon: 30, sequencer: seq,
                                                signatures: clip, target: clip[5])
        XCTAssertEqual(step, 13)
        XCTAssertEqual(seq.index(for: step), 5)
    }

    func testBestUpcomingStepPrefersTheEarliestOfEqualMatches() {
        let clip = (0..<10).map { frame(x: $0 * 2) }
        let seq = PingPongSequencer(frameCount: 10)
        // Index 5 appears at step 13 and again at step 23; take the first.
        XCTAssertEqual(PoseMatcher.bestUpcomingStep(from: 8, horizon: 40, sequencer: seq,
                                                    signatures: clip, target: clip[5]), 13)
    }

    func testBestUpcomingStepFallsBackToNowWithoutSignatures() {
        let seq = PingPongSequencer(frameCount: 10)
        XCTAssertEqual(PoseMatcher.bestUpcomingStep(from: 4, horizon: 30, sequencer: seq,
                                                    signatures: [], target: frame(x: 1)), 4)
    }

    func testIsGoodEnoughThreshold() {
        XCTAssertTrue(PoseMatcher.isCloseEnough(PoseMatcher.distance(frame(x: 10), frame(x: 10))))
        XCTAssertFalse(PoseMatcher.isCloseEnough(PoseMatcher.distance(frame(x: 0), frame(x: 24))))
    }
}
