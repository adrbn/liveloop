//
//  LoopTimerFeature.swift
//  LiveLoop
//
//  Beta — shows how long you've been on the loop next to the menu-bar icon,
//  and optionally nudges you every N minutes ("Still away?"). The 1 s timer
//  only runs while looping with one of the two options on.
//

import Foundation
import Combine

@MainActor
final class LoopTimerFeature: ObservableObject {

    /// "4:12" while looping with the timer on; nil otherwise (plain icon).
    @Published private(set) var elapsedText: String?

    private let settings: BetaSettings
    private let notifier: BetaNotifier
    private weak var host: BetaHost?
    private var clock = LoopSessionClock()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: BetaSettings, notifier: BetaNotifier, host: BetaHost) {
        self.settings = settings
        self.notifier = notifier
        self.host = host
        settings.$loopTimerEnabled.combineLatest(settings.$reminderMinutes)
            .receive(on: DispatchQueue.main)   // @Published fires before the value lands
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func modeDidChange(_ mode: FrameRouter.Mode) {
        if mode == .loop {
            if !clock.isRunning { clock.start(at: Date()) }
        } else {
            clock.stop()
        }
        refresh()
    }

    private func refresh() {
        let wanted = clock.isRunning && (settings.loopTimerEnabled || settings.reminderMinutes > 0)
        guard wanted else {
            timer?.invalidate()
            timer = nil
            elapsedText = nil
            return
        }
        tick()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        let elapsed = LoopSessionClock.format(clock.elapsed(at: now))
        elapsedText = settings.loopTimerEnabled ? elapsed : nil

        let minutes = settings.reminderMinutes
        guard minutes > 0, clock.reminderDue(at: now, every: TimeInterval(minutes * 60)) else { return }
        let hotkey = host?.hotkeyDisplay ?? "the shortcut"
        notifier.post(id: "liveloop.reminder",
                      title: "Still away?",
                      body: "You've been on the loop for \(elapsed). Press \(hotkey) to go live.")
    }
}
