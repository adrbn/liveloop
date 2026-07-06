//
//  PingPongSequencer.swift
//  LiveLoop
//
//  Maps a monotonically increasing step counter onto a "ping-pong" frame index
//  that plays a clip forward, then backward, forever. Because the forward and
//  backward passes share their turning-point frames, the loop has no visible cut
//  — the single most important trick for a believable loop.
//

import Foundation

struct PingPongSequencer {

    /// Number of frames in the clip.
    let frameCount: Int

    init(frameCount: Int) {
        self.frameCount = max(0, frameCount)
    }

    /// The frame index to display at a given zero-based step.
    ///
    /// For a 4-frame clip the produced indices are:
    /// `0,1,2,3,2,1,0,1,2,3,…` — a seamless bounce.
    func index(for step: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        let period = 2 * (frameCount - 1)
        var phase = step % period
        if phase < 0 { phase += period }
        return phase < frameCount ? phase : period - phase
    }
}
