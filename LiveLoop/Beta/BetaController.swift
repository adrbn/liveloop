//
//  BetaController.swift
//  LiveLoop
//
//  Owns the beta features and feeds them the one signal they share: the
//  live / loop mode. With every feature off it only listens; nothing samples
//  the camera, opens audio or runs a timer.
//

import Foundation
import Combine

@MainActor
final class BetaController {

    let settings: BetaSettings
    let loopTimer: LoopTimerFeature
    let nameAlert: NameAlertFeature

    private let notifier = BetaNotifier()
    private let autoAway: AutoAwayFeature
    private weak var host: BetaHost?
    private var cancellables = Set<AnyCancellable>()

    init(host: BetaHost, settings: BetaSettings,
         modes: AnyPublisher<FrameRouter.Mode, Never>, liveFrameTap: LiveFrameTap) {
        self.host = host
        self.settings = settings
        loopTimer = LoopTimerFeature(settings: settings, notifier: notifier, host: host)
        nameAlert = NameAlertFeature(settings: settings, notifier: notifier, host: host)
        autoAway = AutoAwayFeature(settings: settings, tap: liveFrameTap, host: host)

        modes.removeDuplicates()
            .receive(on: DispatchQueue.main)   // deliver after `mode` has actually changed
            .sink { [weak self] mode in self?.modeDidChange(mode) }
            .store(in: &cancellables)
        AutomationCenter.shared.register(self)
    }

    /// Asked the first time a feature that posts notifications is switched on.
    func requestNotificationPermission() {
        notifier.requestPermission()
    }

    private func modeDidChange(_ mode: FrameRouter.Mode) {
        loopTimer.modeDidChange(mode)
        autoAway.modeDidChange(mode)
        nameAlert.modeDidChange(mode)
    }
}

// MARK: - Automations

extension BetaController: AutomationExecutor {

    func handle(url: URL) {
        guard settings.automationsEnabled else {
            host?.notify(.info, "A LiveLoop link was ignored — turn on Automations in Settings ▸ Beta.", sticky: false)
            return
        }
        guard let command = AutomationCommand(url: url) else {
            host?.notify(.failure, "LiveLoop doesn't understand that link.", sticky: false)
            return
        }
        do {
            try run(command)
        } catch {
            host?.notify(.failure, error.localizedDescription, sticky: false)
        }
    }

    func run(_ command: AutomationCommand) throws {
        guard settings.automationsEnabled else { throw AutomationError.disabled }
        guard let host else { throw AutomationError.notReady }
        switch command {
        case .toggle:
            host.toggleLoopLive()
        case .loop:
            Task {
                if !host.isEngaged { await host.engage(onDemand: false) }
                if host.mode != .loop { await host.goToLoop() }
            }
        case .live:
            if host.mode == .loop { host.goToLive() }
        case .startCamera:
            Task { await host.engage(onDemand: false) }
        case .stopCamera:
            host.disengage()
        case .selectClip(let name):
            guard host.selectClip(named: name) else { throw AutomationError.clipNotFound(name) }
        }
    }
}
