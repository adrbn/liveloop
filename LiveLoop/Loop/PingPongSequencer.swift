//
//  PingPongSequencer.swift
//  LiveLoop
//
//  Maps a monotonically increasing step counter onto a "ping-pong" frame index
//  that plays a clip forward, then backward, forever. Because the forward and
//  backward passes share their turning-point frames, the loop has no visible cut
//  — the single most important trick for a believable loop.
//
//  A playlist is several clips laid end to end in one frame array: each clip
//  plays one full bounce (forward, then back to its first frame) before the
//  next one starts. With a single clip this is the plain endless bounce.
//

import Foundation

struct PingPongSequencer {

    /// Frame count of each clip, in play order.
    let segments: [Int]

    init(frameCount: Int) {
        self.init(segments: [frameCount])
    }

    init(segments: [Int]) {
        self.segments = segments.map { max(0, $0) }.filter { $0 > 0 }
    }

    /// Total number of frames across every clip.
    var frameCount: Int { segments.reduce(0, +) }

    /// Steps one clip's bounce lasts (a single-frame clip still shows once).
    private static func period(_ count: Int) -> Int { max(1, 2 * (count - 1)) }

    /// The frame index to display at a given zero-based step.
    ///
    /// For a 4-frame clip the produced indices are:
    /// `0,1,2,3,2,1,0,1,2,3,…` — a seamless bounce.
    func index(for step: Int) -> Int {
        let total = segments.reduce(0) { $0 + Self.period($1) }
        guard total > 0 else { return 0 }
        var phase = step % total
        if phase < 0 { phase += total }
        var offset = 0
        for count in segments {
            let period = Self.period(count)
            if phase < period {
                return offset + (phase < count ? phase : period - phase)
            }
            phase -= period
            offset += count
        }
        return 0
    }

    /// The first step that shows `frame` on its forward pass (inverse of `index`).
    func step(forFrame frame: Int) -> Int {
        var offset = 0, start = 0
        for count in segments {
            if frame < offset + count { return start + max(0, frame - offset) }
            offset += count
            start += Self.period(count)
        }
        return 0
    }
}
