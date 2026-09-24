//
//  LiveLoopIntents.swift
//  LiveLoop
//
//  Beta — Shortcuts actions. They appear in the Shortcuts app under LiveLoop
//  and do nothing (with a clear message) until Automations is turned on in
//  Settings ▸ Beta.
//

import AppIntents

struct ToggleLoopIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Live / Loop"
    static let description = IntentDescription("Switches LiveLoop between your live camera and your loop, like the keyboard shortcut.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try AutomationCenter.shared.run(.toggle)
        return .result()
    }
}

struct GoToLoopIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to Loop"
    static let description = IntentDescription("Turns the camera on if needed and switches to your selected loop.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try AutomationCenter.shared.run(.loop)
        return .result()
    }
}

struct GoLiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Go Live"
    static let description = IntentDescription("Crossfades from the loop back to your live camera.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try AutomationCenter.shared.run(.live)
        return .result()
    }
}

struct StartCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn LiveLoop Camera On"
    static let description = IntentDescription("Starts the LiveLoop camera, live.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try AutomationCenter.shared.run(.startCamera)
        return .result()
    }
}

struct StopCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn LiveLoop Camera Off"
    static let description = IntentDescription("Stops the LiveLoop camera.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try AutomationCenter.shared.run(.stopCamera)
        return .result()
    }
}

struct UseClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Use Loop Clip"
    static let description = IntentDescription("Selects one of your saved clips by name.")

    @Parameter(title: "Clip name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= AutomationCommand.maxClipNameLength else {
            throw AutomationError.clipNotFound(trimmed)
        }
        try AutomationCenter.shared.run(.selectClip(trimmed))
        return .result()
    }
}
