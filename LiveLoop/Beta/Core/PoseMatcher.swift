//
//  PoseMatcher.swift
//  LiveLoop
//
//  Beta — smart switch. Every frame gets a tiny 32×18 grayscale "signature".
//  Comparing signatures tells us which loop frame looks most like you right
//  now, so the loop can start on that frame and the return to live can wait
//  for the moment the loop lines up with you again: no visible jump.
//
//  The distance subtracts each signature's mean first, so a camera
//  auto-exposure change isn't mistaken for a different pose.
//

import Foundation

enum PoseMatcher {

    static let signatureWidth = 32
    static let signatureHeight = 18
    static let signatureLength = signatureWidth * signatureHeight

    /// Distances at or below this look like "the same pose" to a viewer.
    static let closeEnoughDistance = 0.08

    /// Mean-subtracted mean absolute difference in `[0, 1]`, or `.infinity`
    /// when the signatures can't be compared.
    static func distance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return .infinity }
        let meanA = mean(of: a)
        let meanB = mean(of: b)
        var total = 0.0
        for i in a.indices {
            total += abs((Double(a[i]) - meanA) - (Double(b[i]) - meanB))
        }
        return total / Double(a.count) / 255
    }

    static func isCloseEnough(_ distance: Double) -> Bool {
        distance <= closeEnoughDistance
    }

    /// Index of the signature closest to `target`, or nil for an empty clip.
    static func bestIndex(in signatures: [[UInt8]], matching target: [UInt8]) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, signature) in signatures.enumerated() {
            let d = distance(signature, target)
            if d < (best?.distance ?? .infinity) { best = (index, d) }
        }
        return best?.index
    }

    /// The earliest step in `step...step + horizon` whose ping-pong frame best
    /// matches `target`. Returns `step` itself when there's nothing to compare.
    static func bestUpcomingStep(from step: Int, horizon: Int, sequencer: PingPongSequencer,
                                 signatures: [[UInt8]], target: [UInt8]) -> Int {
        guard !signatures.isEmpty, horizon > 0 else { return step }
        var bestStep = step
        var bestDistance = Double.infinity
        for candidate in step...(step + horizon) {
            let index = sequencer.index(for: candidate)
            guard signatures.indices.contains(index) else { continue }
            let d = distance(signatures[index], target)
            if d < bestDistance {
                bestDistance = d
                bestStep = candidate
            }
        }
        return bestStep
    }

    private static func mean(of values: [UInt8]) -> Double {
        Double(values.reduce(0) { $0 + Int($1) }) / Double(values.count)
    }
}
