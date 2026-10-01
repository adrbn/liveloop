//
//  PreviewWindowLayout.swift
//  LiveLoop
//
//  How the big preview window arranges what viewers see and your real camera,
//  and the window size that fits its 16:9 pictures with no bars.
//

import CoreGraphics

enum PreviewWindowLayout: String, CaseIterable, Identifiable {
    /// The two pictures next to each other.
    case sideBySide
    /// Your camera, see-through, on top of what viewers see: line yourself up
    /// with the loop before you switch back.
    case overlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: return "Side by side"
        case .overlay: return "Overlay"
        }
    }

    /// Opacity of your real camera in this layout.
    var liveOpacity: Double {
        switch self {
        case .sideBySide: return 1
        case .overlay: return 0.5
        }
    }

    /// Pictures shown next to each other.
    var paneCount: Int { self == .sideBySide ? 2 : 1 }

    /// Window content size that fits the pictures exactly at `paneHeight`.
    func contentSize(paneHeight: Double, titleBar: Double, gap: Double) -> CGSize {
        let paneWidth = paneHeight * 16 / 9
        let count = Double(paneCount)
        return CGSize(width: count * paneWidth + (count + 1) * gap,
                      height: titleBar + paneHeight + gap)
    }

    /// The picture height a window of `contentHeight` leaves room for.
    static func paneHeight(contentHeight: Double, titleBar: Double, gap: Double) -> Double {
        max(contentHeight - titleBar - gap, 1)
    }

    /// Reads a persisted value, falling back to side by side.
    init(storedValue: String?) {
        self = storedValue.flatMap(PreviewWindowLayout.init(rawValue:)) ?? .sideBySide
    }
}
