//
//  MenuBarLabel.swift
//  LiveLoop
//
//  The menu-bar icon. Identical to the plain icon unless the beta loop timer
//  is on and you're looping, in which case the elapsed time sits beside it.
//

import SwiftUI

struct MenuBarLabel: View {
    let symbol: String
    @ObservedObject var loopTimer: LoopTimerFeature
    /// Receives a way to open windows: the label is the only view SwiftUI
    /// builds at launch, before the menu is ever opened.
    var onLaunch: (OpenWindowAction) -> Void = { _ in }

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        icon.onAppear { onLaunch(openWindow) }
    }

    @ViewBuilder
    private var icon: some View {
        if let elapsed = loopTimer.elapsedText {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text(elapsed).monospacedDigit()
            }
        } else {
            Label("LiveLoop", systemImage: symbol)
        }
    }
}
