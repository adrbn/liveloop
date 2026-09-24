//
//  ConnectionSimulator.swift
//  LiveLoop
//
//  Beta — connection profiles. A perfect, buttery loop can look suspicious;
//  real calls stutter, go blocky and occasionally drop. Each profile answers,
//  per output tick: should the clip advance (or freeze), and how good is the
//  picture right now (1 = pristine, lower = blockier)?
//
//  Deterministic for a given seed, like `LagScheduler`, so it's testable.
//

import Foundation

enum ConnectionProfile: String, CaseIterable, Identifiable {
    case off
    case shakyWiFi
    case mobile4G
    case droppingOut

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .shakyWiFi: return "Shaky Wi-Fi"
        case .mobile4G: return "4G on the go"
        case .droppingOut: return "Dropping out"
        }
    }

    var summary: String {
        switch self {
        case .off: return "Smooth, like a good connection."
        case .shakyWiFi: return "Short hiccups and brief soft patches."
        case .mobile4G: return "Frequent quality drops that get properly blocky."
        case .droppingOut: return "Now and then the picture freezes for a few seconds."
        }
    }
}

struct Impairment: Equatable {
    /// `false` holds the current frame (a freeze).
    let advance: Bool
    /// Picture quality in `(0, 1]`.
    let quality: Double

    static let pristine = Impairment(advance: true, quality: 1)
}

struct ConnectionSimulator {

    let profile: ConnectionProfile

    private let recipe: Recipe?
    private var rng: SplitMix64
    private var freezeRemaining = 0
    private var freezeIsDrop = false
    private var steadyRemaining = 0
    private var dipLength = 0
    private var dipRemaining = 0
    private var dipFloor = 1.0

    init(profile: ConnectionProfile, seed: UInt64) {
        self.profile = profile
        self.recipe = Recipe.for(profile)
        self.rng = SplitMix64(seed: seed)
    }

    mutating func next() -> Impairment {
        guard let recipe else { return .pristine }
        let advance = nextAdvance(recipe)
        let quality = nextQuality(recipe)
        return Impairment(advance: advance, quality: quality)
    }

    // MARK: - Freezes

    private mutating func nextAdvance(_ r: Recipe) -> Bool {
        if freezeRemaining == 0 {
            if steadyRemaining > 0 {
                steadyRemaining -= 1
                return true
            }
            rollFreeze(r)
            if freezeRemaining == 0 { return true }
        }
        freezeRemaining -= 1
        if freezeRemaining == 0 { endFreeze(r) }
        return false
    }

    private mutating func rollFreeze(_ r: Recipe) {
        let roll = rng.nextUnit()
        if roll < r.dropChance {
            freezeRemaining = pick(r.dropTicks)
            freezeIsDrop = true
        } else if roll < r.dropChance + r.stutterChance {
            freezeRemaining = pick(r.stutterTicks)
            freezeIsDrop = false
        }
    }

    private mutating func endFreeze(_ r: Recipe) {
        // Video catches up after a freeze, so never chain two back to back.
        steadyRemaining = r.steadyTicksAfterFreeze
        if freezeIsDrop, let recovery = r.recoveryFloor {
            startDip(ticks: pick(r.dipTicks), floor: pick(recovery))
        }
    }

    // MARK: - Quality dips

    private mutating func nextQuality(_ r: Recipe) -> Double {
        if dipRemaining == 0 {
            guard rng.nextUnit() < r.dipChance else { return 1 }
            startDip(ticks: pick(r.dipTicks), floor: pick(r.dipFloor))
        }
        let progress = Double(dipLength - dipRemaining) / Double(dipLength)
        dipRemaining -= 1
        // Smooth in and out: pristine at the edges, `dipFloor` in the middle.
        return 1 - (1 - dipFloor) * sin(.pi * progress)
    }

    private mutating func startDip(ticks: Int, floor: Double) {
        dipLength = max(1, ticks)
        dipRemaining = dipLength
        dipFloor = floor
    }

    // MARK: - Random helpers

    private mutating func pick(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + rng.nextInt(upTo: range.count)
    }

    private mutating func pick(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + rng.nextUnit() * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Profile recipes (tuned for a 30 fps tick)

private struct Recipe {
    let stutterChance: Double
    let stutterTicks: ClosedRange<Int>
    let dropChance: Double
    let dropTicks: ClosedRange<Int>
    let steadyTicksAfterFreeze: Int
    let dipChance: Double
    let dipTicks: ClosedRange<Int>
    let dipFloor: ClosedRange<Double>
    /// Quality right after a long drop, when the stream comes back blurry.
    let recoveryFloor: ClosedRange<Double>?

    static func `for`(_ profile: ConnectionProfile) -> Recipe? {
        switch profile {
        case .off:
            return nil
        case .shakyWiFi:
            return Recipe(stutterChance: 0.012, stutterTicks: 2...12,
                          dropChance: 0, dropTicks: 1...1,
                          steadyTicksAfterFreeze: 10,
                          dipChance: 0.005, dipTicks: 30...90, dipFloor: 0.45...0.8,
                          recoveryFloor: nil)
        case .mobile4G:
            return Recipe(stutterChance: 0.01, stutterTicks: 3...20,
                          dropChance: 0.0015, dropTicks: 20...40,
                          steadyTicksAfterFreeze: 12,
                          dipChance: 0.012, dipTicks: 45...150, dipFloor: 0.12...0.5,
                          recoveryFloor: 0.12...0.3)
        case .droppingOut:
            return Recipe(stutterChance: 0.008, stutterTicks: 2...8,
                          dropChance: 0.0025, dropTicks: 45...150,
                          steadyTicksAfterFreeze: 20,
                          dipChance: 0.003, dipTicks: 30...60, dipFloor: 0.3...0.6,
                          recoveryFloor: 0.15...0.35)
        }
    }
}
