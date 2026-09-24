//
//  PresenceDetectorTests.swift
//  LiveLoopTests
//
//  Beta — auto away / auto return. The detector turns noisy per-frame
//  "is someone there?" answers into two clean events with hysteresis.
//

import XCTest

final class PresenceDetectorTests: XCTestCase {

    private func detector() -> PresenceDetector {
        PresenceDetector(awayAfter: 8, returnAfter: 1.5, startingAt: 0)
    }

    /// Feeds `present` samples every `step` seconds over `from..<to` and returns the events.
    private func feed(_ d: inout PresenceDetector, present: Bool,
                      from: Double, to: Double, step: Double = 0.4) -> [PresenceDetector.Event] {
        var events: [PresenceDetector.Event] = []
        var t = from
        while t < to {
            if let e = d.observe(present: present, at: t) { events.append(e) }
            t += step
        }
        return events
    }

    func testStaysPresentWhileSomeoneIsThere() {
        var d = detector()
        XCTAssertEqual(feed(&d, present: true, from: 0, to: 60), [])
        XCTAssertEqual(d.state, .present)
    }

    func testLeavesOnlyAfterTheAwayDelay() {
        var d = detector()
        _ = feed(&d, present: true, from: 0, to: 10)
        XCTAssertEqual(feed(&d, present: false, from: 10, to: 17.5), [], "not yet 8 s without anyone")
        XCTAssertEqual(feed(&d, present: false, from: 17.6, to: 19), [.left])
        XCTAssertEqual(d.state, .away)
    }

    func testEmptyFromTheStartCountsFromReset() {
        var d = detector()
        XCTAssertEqual(feed(&d, present: false, from: 0, to: 7.9), [])
        XCTAssertEqual(feed(&d, present: false, from: 8, to: 9), [.left])
    }

    func testBriefMissesNeverTriggerAway() {
        var d = detector()
        var events: [PresenceDetector.Event] = []
        // Face detection drops out for ~2 s every 5 s (looking down, turning away).
        for cycle in 0..<20 {
            let base = Double(cycle) * 5
            events += feed(&d, present: true, from: base, to: base + 3)
            events += feed(&d, present: false, from: base + 3, to: base + 5)
        }
        XCTAssertEqual(events, [])
    }

    func testReturnsAfterContinuousPresence() {
        var d = detector()
        _ = feed(&d, present: false, from: 0, to: 9)
        XCTAssertEqual(d.state, .away)
        XCTAssertEqual(feed(&d, present: true, from: 20, to: 21.2), [], "not yet 1.5 s")
        XCTAssertEqual(feed(&d, present: true, from: 21.6, to: 22.4), [.returned])
        XCTAssertEqual(d.state, .present)
    }

    func testFlickerWhileAwayDoesNotReturn() {
        var d = detector()
        _ = feed(&d, present: false, from: 0, to: 9)
        var events: [PresenceDetector.Event] = []
        // Someone walks past: a face for 0.8 s, then gone for 1.2 s, repeatedly.
        for cycle in 0..<10 {
            let base = 10 + Double(cycle) * 2
            events += feed(&d, present: true, from: base, to: base + 0.8)
            events += feed(&d, present: false, from: base + 0.8, to: base + 2)
        }
        XCTAssertEqual(events, [])
        XCTAssertEqual(d.state, .away)
    }

    func testResetStartsFreshAsPresent() {
        var d = detector()
        _ = feed(&d, present: false, from: 0, to: 9)
        d.reset(at: 30)
        XCTAssertEqual(d.state, .present)
        XCTAssertEqual(feed(&d, present: false, from: 30, to: 37.9), [])
        XCTAssertEqual(feed(&d, present: false, from: 38, to: 39), [.left])
    }

    func testClampsNonsenseDelays() {
        var d = PresenceDetector(awayAfter: -3, returnAfter: 0, startingAt: 0)
        // Minimums keep a single dropped frame from flipping state.
        XCTAssertNil(d.observe(present: false, at: 0.2))
        XCTAssertGreaterThanOrEqual(d.awayAfter, 1)
        XCTAssertGreaterThanOrEqual(d.returnAfter, 0.5)
    }
}
