//
//  LiveLoopApp.swift
//  LiveLoop
//
//  App entry point. LiveLoop is a menu-bar-only app (LSUIElement), so its whole
//  UI hangs off a MenuBarExtra, plus a Settings scene and a one-time onboarding
//  window.
//

import SwiftUI

@main
struct LiveLoopApp: App {

    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
        } label: {
            Label("LiveLoop", systemImage: menuBarSymbol)
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
