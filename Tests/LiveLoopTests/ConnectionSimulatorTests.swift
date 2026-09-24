//
//  ConnectionSimulatorTests.swift
//  LiveLoopTests
//
//  Beta — connection profiles that make the loop read like a real, imperfect
//  network (shaky Wi-Fi, 4G, dropping out) instead of a perfect replay.
//

import XCTest

final class ConnectionSimulatorTests: XCTestCase {

    private struct Stats {
        var frozenTicks = 0
        var longestFreeze = 0
        var degradedTicks = 0
        var lowestQuality = 1.0
    }

    private func run(_ profile: ConnectionProfile, seed: UInt64 = 42, ticks: Int = 30_000) -> Stats {
        var sim = ConnectionSimulator(profile: profile, seed: seed)
        var stats = Stats()
        var currentFreeze = 0
        for _ in 0..<ticks {
            let impairment = sim.next()
            XCTAssertTrue(impairment.quality > 0 && impairment.quality <= 1, "quality out of range")
            if impairment.advance {
                currentFreeze = 0
            } else {
                stats.frozenTicks += 1
                currentFreeze += 1
                stats.longestFreeze = max(stats.longestFreeze, currentFreeze)
            }
            if impairment.quality < 0.999 { stats.degradedTicks += 1 }
            stats.lowestQuality = min(stats.lowestQuality, impairment.quality)
        }
        return stats
    }

    func testOffIsPristine() {
        var sim = ConnectionSimulator(profile: .off, seed: 1)
        for _ in 0..<10_000 {
            XCTAssertEqual(sim.next(), Impairment.pristine)
        }
    }

    func testDeterministicForSameSeed() {
        for profile in ConnectionProfile.allCases {
            var a = ConnectionSimulator(profile: profile, seed: 9)
            var b = ConnectionSimulator(profile: profile, seed: 9)
            for _ in 0..<5_000 {
                XCTAssertEqual(a.next(), b.next())
            }
        }
    }

    func testShakyWiFiHasShortFreezesAndMildDips() {
        let s = run(.shakyWiFi)
        XCTAssertGreaterThan(s.frozenTicks, 0)
        XCTAssertLessThanOrEqual(s.longestFreeze, 15, "Wi-Fi hiccups stay short")
        XCTAssertGreaterThan(s.degradedTicks, 0)
        XCTAssertGreaterThanOrEqual(s.lowestQuality, 0.3, "Wi-Fi dips are mild")
        XCTAssertLessThan(Double(s.frozenTicks) / 30_000, 0.2, "mostly smooth")
    }

    func testMobileHasDeeperQualityDrops() {
        let s = run(.mobile4G)
        XCTAssertGreaterThan(s.frozenTicks, 0)
        XCTAssertLessThan(s.lowestQuality, 0.3, "4G gets properly blocky")
        XCTAssertGreaterThan(s.degradedTicks, run(.shakyWiFi).degradedTicks)
    }

    func testDroppingOutHasLongFreezes() {
        let s = run(.droppingOut)
        XCTAssertGreaterThanOrEqual(s.longestFreeze, 45, "at least one 1.5 s+ drop")
        XCTAssertLessThanOrEqual(s.longestFreeze, 150, "never frozen for more than 5 s")
        XCTAssertLessThan(Double(s.frozenTicks) / 30_000, 0.35, "still mostly moving")
    }

    func testEveryProfileHasADisplayName() {
        for profile in ConnectionProfile.allCases {
            XCTAssertFalse(profile.displayName.isEmpty)
        }
    }
}
