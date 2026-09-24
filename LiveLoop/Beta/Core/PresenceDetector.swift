//
//  PresenceDetector.swift
//  LiveLoop
//
//  Beta — auto away / auto return. Face detection is noisy: it misses you when
//  you look down, and it can catch someone walking past. This state machine
//  turns those per-frame answers into two clean events using hysteresis:
//
//  • `.left`     after nobody has been seen for `awayAfter` seconds.
//  • `.returned` after someone has been seen continuously for `returnAfter`
//                seconds (gaps shorter than `dropoutTolerance` don't break it).
//
//  Times are plain seconds on any monotonic clock.
//

import Foundation

struct PresenceDetector {

    enum State: Equatable { case present, away }
    enum Event: Equatable { case left, returned }

    static let minimumAwayAfter: TimeInterval = 1
    static let minimumReturnAfter: TimeInterval = 0.5
    static let dropoutTolerance: TimeInterval = 0.7

    let awayAfter: TimeInterval
    let returnAfter: TimeInterval

    private(set) var state: State = .present
    private var lastSeen: TimeInterval
    private var streakStart: TimeInterval?
    private var lastPresentSample: TimeInterval?

    init(awayAfter: TimeInterval, returnAfter: TimeInterval, startingAt now: TimeInterval) {
        self.awayAfter = max(Self.minimumAwayAfter, awayAfter)
        self.returnAfter = max(Self.minimumReturnAfter, returnAfter)
        self.lastSeen = now
    }

    /// Starts over as "present" (e.g. when the camera restarts or you go live by hand).
    mutating func reset(at now: TimeInterval) {
        state = .present
        lastSeen = now
        streakStart = nil
        lastPresentSample = nil
    }

    /// Feeds one detection result. Returns an event only on a state change.
    mutating func observe(present: Bool, at now: TimeInterval) -> Event? {
        switch state {
        case .present:
            if present {
                lastSeen = now
                return nil
            }
            guard now - lastSeen >= awayAfter else { return nil }
            state = .away
            streakStart = nil
            lastPresentSample = nil
            return .left

        case .away:
            guard present else { return nil }
            if let last = lastPresentSample, now - last <= Self.dropoutTolerance, streakStart != nil {
                // Still the same continuous streak.
            } else {
                streakStart = now
            }
            lastPresentSample = now
            guard let start = streakStart, now - start >= returnAfter else { return nil }
            state = .present
            lastSeen = now
            streakStart = nil
            lastPresentSample = nil
            return .returned
        }
    }
}
