//
//  LiveLoopApp.swift
//  LiveLoop
//
//  App entry point. LiveLoop is a menu-bar-only app (LSUIElement), so its whole
//  UI hangs off a MenuBarExtra, plus a Settings scene, a one-time onboarding
//  window and a floating preview window.
//

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
            MenuBarLabel(symbol: menuBarSymbol, loopTimer: appState.betaController.loopTimer)
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
        .defaultSize(width: 780, height: 260)
        .defaultPosition(.topTrailing)
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
