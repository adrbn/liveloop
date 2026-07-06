//
//  LagScheduler.swift
//  LiveLoop
//
//  Produces the "simulated lag" effect: occasional, never-repeating micro-
//  freezes and stutters so the loop reads like a flaky connection rather than a
//  frozen app. Deterministic given a seed, which keeps it unit-testable while
//  still looking irregular to a viewer.
//
//  The scheduler answers one question per output tick: should the underlying
//  clip advance this tick, or hold the current frame (a freeze)?
//

import Foundation

struct LagScheduler {

    /// 0 = disabled (always advance), 1 = maximum stutter.
    var intensity: Double

    private var rng: SplitMix64
    private var freezeTicksRemaining: Int = 0

    init(intensity: Double, seed: UInt64) {
        self.intensity = min(max(intensity, 0), 1)
        self.rng = SplitMix64(seed: seed)
    }

    /// Returns `true` if the clip should advance this tick, `false` to hold the
    /// current frame (a freeze). With `intensity == 0` this always returns
    /// `true`.
    mutating func shouldAdvance() -> Bool {
        guard intensity > 0 else { return true }

        if freezeTicksRemaining > 0 {
            freezeTicksRemaining -= 1
            return false
        }

        // Probability of starting a freeze on any given tick.
        let startProbability = intensity * 0.12
        if rng.nextUnit() < startProbability {
            // Freeze length scales with intensity: up to ~0.6 s at 30 fps.
            let maxFreeze = Int(2 + intensity * 16)
            freezeTicksRemaining = 1 + rng.nextInt(upTo: maxFreeze)
            return false
        }
        return true
    }
}
