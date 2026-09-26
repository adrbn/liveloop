//
//  PreviewContent.swift
//  LiveLoop
//
//  What the panel's preview card shows for the current camera state.
//

enum PreviewContent: Equatable {
    /// Camera on: exactly what viewers see.
    case output
    /// Recording with the camera off: your webcam, seen only by you.
    case selfView
    /// Camera off, a clip selected: the loop that's ready to play.
    case loopReady
    /// Camera off, nothing recorded yet.
    case noClip

    static func resolve(engaged: Bool, recording: Bool, hasClip: Bool) -> PreviewContent {
        if engaged { return .output }
        if recording { return .selfView }
        return hasClip ? .loopReady : .noClip
    }
}
