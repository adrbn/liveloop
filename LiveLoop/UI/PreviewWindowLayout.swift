//
//  PreviewWindowLayout.swift
//  LiveLoop
//
//  How the big preview window arranges what viewers see and your real camera.
//

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

    /// Reads a persisted value, falling back to side by side.
    init(storedValue: String?) {
        self = storedValue.flatMap(PreviewWindowLayout.init(rawValue:)) ?? .sideBySide
    }
}
