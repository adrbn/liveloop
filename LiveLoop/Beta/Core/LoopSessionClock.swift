//
//  LoopSessionClock.swift
//  LiveLoop
//
//  Beta — how long you've been "away" on the loop. Drives the menu-bar timer
//  and the optional "still away?" reminder, which fires at most once per
//  interval even if the app was asleep and a tick arrives late.
//

import Foundation

struct LoopSessionClock {

    private(set) var startedAt: Date?
    private var remindersFired = 0

    var isRunning: Bool { startedAt != nil }

    mutating func start(at date: Date) {
        startedAt = date
        remindersFired = 0
    }

    mutating func stop() {
        startedAt = nil
        remindersFired = 0
    }

    /// Seconds since `start(at:)`, or 0 when not running.
    func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    /// `true` once each time another full `interval` has elapsed.
    mutating func reminderDue(at now: Date, every interval: TimeInterval) -> Bool {
        guard isRunning, interval > 0, interval.isFinite else { return false }
        let intervalsElapsed = Int(elapsed(at: now) / interval)
        guard intervalsElapsed > remindersFired else { return false }
        remindersFired = intervalsElapsed
        return true
    }

    /// "0:07", "4:12", "1:02:03".
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
