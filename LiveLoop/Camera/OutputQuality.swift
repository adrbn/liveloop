//
//  OutputQuality.swift
//  LiveLoop
//
//  How much detail the virtual camera sends. The frame size never changes —
//  meeting apps expect the one format the extension advertises — so 720p
//  renders the picture at 1280×720 first and stretches it back, which softens
//  it. Live and loop get the same treatment, so switching stays seamless.
//

import Foundation

enum OutputQuality: String, CaseIterable, Identifiable {
    case fullHD = "1080p"
    case hd = "720p"

    var id: String { rawValue }

    /// Rendered height as a fraction of the output height (1 = untouched).
    var detailScale: Double {
        switch self {
        case .fullHD: return 1
        case .hd: return 720 / Double(LiveLoop.frameHeight)
        }
    }

    /// The size the picture is rendered at before it fills the output frame.
    var renderedSize: CGSize {
        CGSize(width: Double(LiveLoop.frameWidth) * detailScale,
               height: Double(LiveLoop.frameHeight) * detailScale)
    }

    /// Reads a persisted value, falling back to full quality.
    init(storedValue: String?) {
        self = storedValue.flatMap(OutputQuality.init(rawValue:)) ?? .fullHD
    }
}
