//
//  LiveLoopApp.swift
//  LiveLoop
//
//  App entry point. LiveLoop is a menu-bar-only app (LSUIElement), so its whole
//  UI hangs off a MenuBarExtra, plus a Settings scene, a one-time onboarding
//  window and a floating preview window.
//

import AVFoundation
import SwiftUI

@main
struct LiveLoopApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel(symbol: menuBarSymbol, loopTimer: appState.betaController.loopTimer,
                         onLaunch: showSetupOnFirstRun)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("Set up LiveLoop", id: "onboarding") {
            OnboardingView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("LiveLoop Preview", id: PreviewWindowView.windowID) {
            PreviewWindowView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 808, height: 260) // side by side, no bars
        .defaultPosition(.topTrailing)
    }

    /// First run opens setup by itself, so nobody has to find the menu-bar
    /// icon first. The Dock icon opens it again.
    private func showSetupOnFirstRun(_ openWindow: OpenWindowAction) {
        guard appDelegate.showSetup == nil else { return } // once per launch
        let showSetup = {
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        }
        appDelegate.showSetup = showSetup
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { showSetup() }
    }

    private var menuBarSymbol: String {
        if appState.isRecording { return "record.circle" }
        switch appState.mode {
        case .loop: return "repeat.circle.fill"
        case .live: return "video.circle.fill"
        case .idle: return "video.circle"
        }
    }
}
