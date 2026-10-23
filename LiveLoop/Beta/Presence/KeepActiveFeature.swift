//
//  KeepActiveFeature.swift
//  LiveLoop
//
//  Beta — while you're on the loop and the Mac has been idle for a minute,
//  move the pointer by one pixel and back, so Teams, Slack & co. don't mark
//  you Away. Without the Accessibility permission the nudge still resets the
//  system idle timer, but only with it do apps see the move as input.
//  Stops the moment you go live.
//

import AppKit
import ApplicationServices
import Combine

@MainActor
final class KeepActiveFeature {

    private static let checkEvery: TimeInterval = 15
    private static let anyInput = CGEventType(rawValue: ~0)!

    private let settings: BetaSettings
    private var mode: FrameRouter.Mode = .idle
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: BetaSettings) {
        self.settings = settings
        settings.$keepActiveEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled { self?.requestPermission() }
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func modeDidChange(_ newMode: FrameRouter.Mode) {
        mode = newMode
        refresh()
    }

    // MARK: - Private

    /// Shows the system prompt (with its own Open System Settings button) when
    /// LiveLoop isn't allowed in Privacy & Security ▸ Accessibility yet.
    private func requestPermission() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    private func refresh() {
        guard settings.keepActiveEnabled, mode == .loop else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
        guard KeepActivePolicy.shouldNudge(isLooping: mode == .loop, idleSeconds: idle),
              let here = CGEvent(source: nil)?.location else { return }
        for dx in [1.0, 0.0] {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: CGPoint(x: here.x + dx, y: here.y), mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}
