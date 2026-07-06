//
//  LoopEngineTests.swift
//  LiveLoopTests
//
//  Pure-logic tests for the loop primitives — the parts a wrong edit would
//  silently break: seamless ping-pong indexing and deterministic simulated lag.
//

import XCTest

final class PingPongSequencerTests: XCTestCase {

    func testBounceSequenceForFourFrames() {
        let seq = PingPongSequencer(frameCount: 4)
        let produced = (0..<9).map { seq.index(for: $0) }
        XCTAssertEqual(produced, [0, 1, 2, 3, 2, 1, 0, 1, 2])
    }

    func testSingleFrameAlwaysZero() {
        let seq = PingPongSequencer(frameCount: 1)
        XCTAssertEqual((0..<5).map { seq.index(for: $0) }, [0, 0, 0, 0, 0])
    }

    func testEmptyClipIsSafe() {
        let seq = PingPongSequencer(frameCount: 0)
        XCTAssertEqual(seq.index(for: 3), 0)
    }

    func testIndicesAlwaysInRange() {
        let seq = PingPongSequencer(frameCount: 7)
        for step in 0..<1000 {
            let i = seq.index(for: step)
            XCTAssertTrue(i >= 0 && i < 7, "index \(i) out of range at step \(step)")
        }
    }

    func testTurningPointsHaveNoRepeatedCut() {
        // The frame *after* the last should be the second-to-last (a bounce),
        // never a jump straight back to zero.
        let seq = PingPongSequencer(frameCount: 5)   // period 8
        XCTAssertEqual(seq.index(for: 4), 4)          // last frame
        XCTAssertEqual(seq.index(for: 5), 3)          // bounces back, not to 0
    }
}

final class LagSchedulerTests: XCTestCase {

    func testDisabledAlwaysAdvances() {
        var lag = LagScheduler(intensity: 0, seed: 42)
        for _ in 0..<10_000 {
            XCTAssertTrue(lag.shouldAdvance())
        }
    }

    func testDeterministicForSameSeed() {
        var a = LagScheduler(intensity: 0.8, seed: 123)
        var b = LagScheduler(intensity: 0.8, seed: 123)
        for _ in 0..<5_000 {
            XCTAssertEqual(a.shouldAdvance(), b.shouldAdvance())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = LagScheduler(intensity: 0.8, seed: 1)
        var b = LagScheduler(intensity: 0.8, seed: 2)
        var differences = 0
        for _ in 0..<5_000 where a.shouldAdvance() != b.shouldAdvance() {
            differences += 1
        }
        XCTAssertGreaterThan(differences, 0, "distinct seeds should diverge")
    }

    func testEnabledProducesFreezes() {
        var lag = LagScheduler(intensity: 1.0, seed: 7)
        var freezes = 0
        for _ in 0..<5_000 where !lag.shouldAdvance() {
            freezes += 1
        }
        XCTAssertGreaterThan(freezes, 0, "high intensity should freeze sometimes")
        XCTAssertLessThan(freezes, 5_000, "should not freeze forever")
    }
}

final class SplitMix64Tests: XCTestCase {

    func testDeterministic() {
        var a = SplitMix64(seed: 999)
        var b = SplitMix64(seed: 999)
        for _ in 0..<1_000 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testUnitRange() {
        var rng = SplitMix64(seed: 5)
        for _ in 0..<10_000 {
            let u = rng.nextUnit()
            XCTAssertTrue(u >= 0 && u < 1)
        }
    }

    func testIntUpperBound() {
        var rng = SplitMix64(seed: 5)
        for _ in 0..<10_000 {
            let n = rng.nextInt(upTo: 13)
            XCTAssertTrue(n >= 0 && n < 13)
        }
    }
}
