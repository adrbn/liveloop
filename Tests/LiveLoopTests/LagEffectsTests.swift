//
//  LagEffectsTests.swift
//  LiveLoopTests
//
//  Simulated lag and the beta connection profiles both freeze the picture;
//  these pin down that exactly one of them runs.
//

import XCTest

final class LagEffectsTests: XCTestCase {

    func testOffMeansNoEffectEvenWithAProfileSelected() {
        let effects = LagEffects(enabled: false, intensity: 0.7, profile: .mobile4G)
        XCTAssertEqual(effects, LagEffects(enabled: true, intensity: 0, profile: .off))
        XCTAssertEqual(effects.stutterIntensity, 0)
        XCTAssertEqual(effects.profile, .off)
    }

    func testStutterStyleUsesTheIntensity() {
        let effects = LagEffects(enabled: true, intensity: 0.7, profile: .off)
        XCTAssertEqual(effects.stutterIntensity, 0.7)
        XCTAssertEqual(effects.profile, .off)
    }

    func testAProfileReplacesTheStutter() {
        for profile in ConnectionProfile.allCases where profile != .off {
            let effects = LagEffects(enabled: true, intensity: 0.7, profile: profile)
            XCTAssertEqual(effects.stutterIntensity, 0, "\(profile) must not stack with the stutter")
            XCTAssertEqual(effects.profile, profile)
        }
    }
}
