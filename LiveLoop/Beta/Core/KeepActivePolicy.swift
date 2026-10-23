//
//  KeepActivePolicy.swift
//  LiveLoop
//
//  Beta — when to nudge the pointer so meeting apps don't mark you Away
//  while you're on the loop. Pure logic, so it's unit-tested.
//

import Foundation

enum KeepActivePolicy {

    /// Teams and Slack flip to Away after ~5 min idle; nudging after one
    /// minute stays well clear of that without moving the pointer much.
    static let idleThreshold: TimeInterval = 60

    static func shouldNudge(isLooping: Bool, idleSeconds: TimeInterval) -> Bool {
        isLooping && idleSeconds >= idleThreshold
    }
}
