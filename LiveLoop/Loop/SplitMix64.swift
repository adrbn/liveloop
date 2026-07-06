//
//  SplitMix64.swift
//  LiveLoop
//
//  A tiny, fast, fully deterministic PRNG. Seeding it identically reproduces the
//  exact same stream — which is what makes the simulated-lag schedule testable.
//

import Foundation

struct SplitMix64: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A double in `[0, 1)`.
    mutating func nextUnit() -> Double {
        // Use the top 53 bits for a uniformly distributed double.
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// An integer in `0 ..< upperBound` (`upperBound` must be > 0).
    mutating func nextInt(upTo upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        return Int(next() % UInt64(upperBound))
    }
}
