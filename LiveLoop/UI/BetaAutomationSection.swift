//
//  BetaAutomationSection.swift
//  LiveLoop
//
//  Settings ▸ Beta ▸ Shortcuts & links. Every link offered here is built by
//  `AutomationCommand.url`, the same type that parses it, and the clip links
//  are your actual clips.
//

import SwiftUI
import AppKit

struct BetaAutomationSection: View {
    @ObservedObject var settings: BetaSettings
    let clipNames: [String]

    @State private var copiedTitle: String?
    @State private var copyGeneration = 0

    private static let shortcutsBundleID = "com.apple.shortcuts"
    private static let copiedDisplayTime: Duration = .seconds(2)

    /// Same names as the Shortcuts actions, so the two read alike.
    private static let commands: [(title: String, command: AutomationCommand)] = [
        ("Toggle Live / Loop", .toggle),
        ("Switch to Loop", .loop),
        ("Go Live", .live),
        ("Turn Camera On", .startCamera),
        ("Turn Camera Off", .stopCamera),
    ]

    var body: some View {
        Section {
            Toggle(isOn: $settings.automationsEnabled.animation()) {
                FeatureLabel(title: "Shortcuts & links",
                             subtitle: "Control LiveLoop from Shortcuts, Stream Deck, Raycast or a script.",
                             symbol: "link", tint: .indigo)
            }
            if settings.automationsEnabled {
                Group {
                    LabeledContent {
                        HStack(spacing: 8) {
                            if let copiedTitle {
                                Label("Copied", systemImage: "checkmark")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .help("Copied the link for “\(copiedTitle)”")
                                    .transition(.opacity)
                            }
                            linkMenu
                        }
                    } label: {
                        Text("Links")
                        Text("Paste one into any app that can open a URL.")
                    }
                    LabeledContent {
                        Button("Open Shortcuts") { openShortcuts() }
                    } label: {
                        Text("Shortcuts")
                        Text("LiveLoop's actions are already listed there.")
                    }
                }
                .padding(.leading, FeatureLabel.optionInset)
            }
        } header: {
            Text("Automate")
        }
    }

    private var linkMenu: some View {
        Menu("Copy Link") {
            ForEach(Self.commands, id: \.title) { item in
                Button(item.title) { copy(item.command, title: item.title) }
            }
            let names = AutomationCommand.linkableClipNames(clipNames)
            if !names.isEmpty {
                Section("Use Clip") {
                    ForEach(names, id: \.self) { name in
                        Button(name) { copy(.selectClip(name), title: name) }
                    }
                }
            }
        }
        .fixedSize()
    }

    private func copy(_ command: AutomationCommand, title: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.url.absoluteString, forType: .string)
        copyGeneration += 1
        let generation = copyGeneration
        withAnimation { copiedTitle = title }
        Task {
            try? await Task.sleep(for: Self.copiedDisplayTime)
            guard generation == copyGeneration else { return }
            withAnimation { copiedTitle = nil }
        }
    }

    private func openShortcuts() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.shortcutsBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
