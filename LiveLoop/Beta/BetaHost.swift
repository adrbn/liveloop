//
//  BetaHost.swift
//  LiveLoop
//
//  The narrow slice of the app the beta features are allowed to touch. They
//  drive LiveLoop exactly like the hotkey does — nothing more.
//

import Foundation

@MainActor
protocol BetaHost: AnyObject {
    var mode: FrameRouter.Mode { get }
    var isEngaged: Bool { get }
    var isRecording: Bool { get }
    var hasClips: Bool { get }
    var hotkeyDisplay: String { get }

    func notify(_ kind: AppBanner.Kind, _ text: String, sticky: Bool)
    func engage(onDemand: Bool) async
    func disengage()
    func goToLoop() async
    func goToLive()
    func toggleLoopLive()
    /// Selects the clip with this name (case- and accent-insensitive).
    func selectClip(named name: String) -> Bool
}

extension AppState: BetaHost {

    var hasClips: Bool { !library.clips.isEmpty }

    var hotkeyDisplay: String { settings.hotkeyDisplayString }

    func selectClip(named name: String) -> Bool {
        let match = library.clips.first { AutomationCommand.clipNamesMatch($0.name, name) }
        guard let match else { return false }
        selectClip(match)
        return true
    }
}
