//
//  SwitchTransitionTests.swift
//  LiveLoopTests
//
//  A switch between live and loop either crossfades or freezes on the last
//  frame viewers saw, then cuts, like a connection hiccup. Both must end, and
//  a bad stored style must fall back to the crossfade.
//

import XCTest

final class SwitchTransitionTests: XCTestCase {

    func testCrossfadeBlendsTowardTheTargetAndEndsFullyOnIt() {
        let transition = SwitchTransition(style: .crossfade, frameRate: 30)
        var previous = 0.0
        for tick in 1...transition.tickCount {
            guard case .blend(let t) = transition.frame(atTick: tick) else {
                return XCTFail("tick \(tick) should blend")
            }
            XCTAssertGreaterThan(t, previous)
            previous = t
        }
        XCTAssertEqual(previous, 1, accuracy: 0.0001)
    }

    func testCrossfadeLastsAboutAThirdOfASecond() {
        let transition = SwitchTransition(style: .crossfade, frameRate: 30)
        XCTAssertEqual(transition.tickCount, 11)
    }

    func testFreezeHoldsTheSameFrameUntilItEnds() {
        let transition = SwitchTransition(style: .freeze, frameRate: 30)
        for tick in 1...transition.tickCount {
            XCTAssertEqual(transition.frame(atTick: tick), .hold, "tick \(tick)")
        }
    }

    func testFreezeLooksLikeAHiccupNotAHang() {
        let transition = SwitchTransition(style: .freeze, frameRate: 30)
        let seconds = Double(transition.tickCount) / 30
        XCTAssertGreaterThanOrEqual(seconds, 0.5)
        XCTAssertLessThanOrEqual(seconds, 1.2)
    }

    func testEveryStyleEnds() {
        for style in SwitchStyle.allCases {
            XCTAssertGreaterThan(SwitchTransition(style: style, frameRate: 30).tickCount, 0, "\(style)")
        }
    }

    func testMissingOrUnknownStoredStyleFallsBackToCrossfade() {
        XCTAssertEqual(SwitchStyle(storedValue: nil), .crossfade)
        XCTAssertEqual(SwitchStyle(storedValue: "wipe"), .crossfade)
    }

    func testStoredStyleRoundTrips() {
        for style in SwitchStyle.allCases {
            XCTAssertEqual(SwitchStyle(storedValue: style.rawValue), style)
        }
    }
}
