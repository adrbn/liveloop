//
//  SwitchTransition.swift
//  LiveLoop
//
//  How a switch between live and loop looks. A crossfade blends the two; a
//  freeze holds the last frame viewers saw, then cuts, the way a call does
//  when the connection hiccups. Pure timing logic: the router supplies frames.
//

import Foundation

enum SwitchStyle: String, CaseIterable, Identifiable {
    case crossfade
    case freeze

    var id: String { rawValue }

    /// How long the switch lasts on screen.
    var seconds: Double {
        switch self {
        case .crossfade: return 0.35
        case .freeze: return 0.8
        }
    }

    /// Reads a persisted value, falling back to the crossfade.
    init(storedValue: String?) {
        self = storedValue.flatMap(SwitchStyle.init(rawValue:)) ?? .crossfade
    }
}

/// One switch, measured in output ticks (one per loop frame).
struct SwitchTransition: Equatable {

    enum Frame: Equatable {
        /// Mix of the frame being left (0) and the target (1).
        case blend(Double)
        /// Repeat the frame viewers saw when the switch began.
        case hold
    }

    let style: SwitchStyle
    /// Ticks until the switch is over and the target plays on its own.
    let tickCount: Int
    private let increment: Double

    init(style: SwitchStyle, frameRate: Int) {
        let ticks = style.seconds * Double(frameRate)
        self.style = style
        self.tickCount = max(1, Int(ticks.rounded(.up)))
        self.increment = 1 / max(ticks, 1)
    }

    /// What to show on `tick` (1-based, up to `tickCount`).
    func frame(atTick tick: Int) -> Frame {
        switch style {
        case .crossfade: return .blend(min(Double(tick) * increment, 1))
        case .freeze: return .hold
        }
    }
}
