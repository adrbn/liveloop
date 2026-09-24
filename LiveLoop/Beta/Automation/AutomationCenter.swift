//
//  AutomationCenter.swift
//  LiveLoop
//
//  Beta — the single entry point for outside automation: `liveloop://` links
//  (Stream Deck, Raycast, Alfred, `open location` in AppleScript) and the
//  Shortcuts actions. Links that arrive before the app has finished starting
//  are held briefly and replayed once it's ready.
//

import Foundation

enum AutomationError: LocalizedError, CustomLocalizedStringResourceConvertible {
    case disabled
    case notReady
    case clipNotFound(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Automations are off. Turn them on in LiveLoop ▸ Settings ▸ Beta."
        case .notReady:
            return "LiveLoop is still starting. Try again in a moment."
        case .clipNotFound(let name):
            return "No clip named “\(name)”."
        }
    }

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: errorDescription ?? "LiveLoop couldn't do that.")
    }
}

@MainActor
protocol AutomationExecutor: AnyObject {
    func handle(url: URL)
    func run(_ command: AutomationCommand) throws
}

@MainActor
final class AutomationCenter {

    static let shared = AutomationCenter()

    private static let maxPendingURLs = 8

    private weak var executor: AutomationExecutor?
    private var pendingURLs: [URL] = []

    func register(_ executor: AutomationExecutor) {
        self.executor = executor
        let queued = pendingURLs
        pendingURLs = []
        queued.forEach(executor.handle(url:))
    }

    func open(_ url: URL) {
        if let executor {
            executor.handle(url: url)
        } else if pendingURLs.count < Self.maxPendingURLs {
            pendingURLs.append(url)
        }
    }

    func run(_ command: AutomationCommand) throws {
        guard let executor else { throw AutomationError.notReady }
        try executor.run(command)
    }
}
