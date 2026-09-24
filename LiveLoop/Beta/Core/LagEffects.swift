//
//  LagEffects.swift
//  LiveLoop
//
//  What Simulated lag does to the next loop: the plain stutter at its
//  intensity (`LagScheduler`), or, in beta, a connection profile
//  (`ConnectionSimulator`) instead. Both freeze the picture, so they never
//  stack: picking a profile replaces the stutter.
//

import Foundation

struct LagEffects: Equatable {
    /// `LagScheduler` intensity; 0 = no stutter.
    let stutterIntensity: Double
    /// `ConnectionSimulator` profile; `.off` = none.
    let profile: ConnectionProfile

    init(enabled: Bool, intensity: Double, profile: ConnectionProfile) {
        guard enabled else {
            self.stutterIntensity = 0
            self.profile = .off
            return
        }
        self.stutterIntensity = profile == .off ? intensity : 0
        self.profile = profile
    }
}
