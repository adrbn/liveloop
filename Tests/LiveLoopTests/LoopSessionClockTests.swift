//
//  LoopSessionClockTests.swift
//  LiveLoopTests
//
//  Beta — menu-bar loop timer and "still away?" reminders.
//

import XCTest

final class LoopSessionClockTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(LoopSessionClock.format(0), "0:00")
        XCTAssertEqual(LoopSessionClock.format(7), "0:07")
        XCTAssertEqual(LoopSessionClock.format(59.9), "0:59")
        XCTAssertEqual(LoopSessionClock.format(252), "4:12")
    }

    func testFormatsHoursWhenNeeded() {
        XCTAssertEqual(LoopSessionClock.format(3_723), "1:02:03")
    }

    func testNegativeOrInvalidDurationsFormatAsZero() {
        XCTAssertEqual(LoopSessionClock.format(-5), "0:00")
        XCTAssertEqual(LoopSessionClock.format(.nan), "0:00")
    }

    func testElapsedIsZeroUntilStarted() {
        let clock = LoopSessionClock()
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0), 0)
    }

    func testElapsedCountsFromStart() {
        var clock = LoopSessionClock()
        clock.start(at: t0)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(90)), 90, accuracy: 0.001)
    }

    func testStopResets() {
        var clock = LoopSessionClock()
        clock.start(at: t0)
        clock.stop()
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(90)), 0)
    }

    func testReminderFiresOncePerInterval() {
        var clock = LoopSessionClock()
        clock.start(at: t0)
        let every: TimeInterval = 600
        XCTAssertFalse(clock.reminderDue(at: t0.addingTimeInterval(599), every: every))
        XCTAssertTrue(clock.reminderDue(at: t0.addingTimeInterval(600), every: every))
        XCTAssertFalse(clock.reminderDue(at: t0.addingTimeInterval(700), every: every), "only once per interval")
        XCTAssertTrue(clock.reminderDue(at: t0.addingTimeInterval(1_201), every: every))
    }

    func testReminderCatchesUpWithoutFiringTwice() {
        // A late tick (e.g. after sleep) fires once, not once per missed interval.
        var clock = LoopSessionClock()
        clock.start(at: t0)
        XCTAssertTrue(clock.reminderDue(at: t0.addingTimeInterval(3_000), every: 600))
        XCTAssertFalse(clock.reminderDue(at: t0.addingTimeInterval(3_001), every: 600))
    }

    func testReminderNeverFiresWhenStoppedOrIntervalInvalid() {
        var clock = LoopSessionClock()
        XCTAssertFalse(clock.reminderDue(at: t0.addingTimeInterval(10_000), every: 600))
        clock.start(at: t0)
        XCTAssertFalse(clock.reminderDue(at: t0.addingTimeInterval(10_000), every: 0))
    }

    func testRestartResetsReminders() {
        var clock = LoopSessionClock()
        clock.start(at: t0)
        XCTAssertTrue(clock.reminderDue(at: t0.addingTimeInterval(600), every: 600))
        clock.start(at: t0.addingTimeInterval(700))
        XCTAssertFalse(clock.reminderDue(at: t0.addingTimeInterval(1_200), every: 600))
        XCTAssertTrue(clock.reminderDue(at: t0.addingTimeInterval(1_300), every: 600))
    }
}
