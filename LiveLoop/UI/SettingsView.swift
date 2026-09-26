//
//  SettingsView.swift
//  LiveLoop
//
//  Preferences window: the shortcut, simulated lag, picture quality, the
//  camera name and the beta features.
//

import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        SettingsTabs(app: app, settings: app.settings, beta: app.beta)
            .frame(width: 480, height: 380)
    }
}

private struct SettingsTabs: View {
    @ObservedObject var app: AppState
    @ObservedObject var settings: Settings
    @ObservedObject var beta: BetaSettings

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            loop.tabItem { Label("Loop", systemImage: "repeat") }
            shortcut.tabItem { Label("Shortcut", systemImage: "keyboard") }
            camera.tabItem { Label("Virtual Camera", systemImage: "video") }
            BetaSettingsView(settings: app.beta, controller: app.betaController,
                             clipNames: app.library.clips.map(\.name))
                .tabItem { Label("Beta", systemImage: "flask") }
        }
        .padding(20)
    }

    // MARK: General

    private var general: some View {
        Form {
            Picker("Camera source", selection: Binding(
                get: { settings.selectedCameraID },
                set: { app.selectCamera($0) })) {
                Text("System default").tag(String?.none)
                ForEach(app.cameras) { cam in
                    Text(cam.name).tag(String?.some(cam.id))
                }
            }

            LabeledContent("Clip length") {
                VStack(alignment: .leading) {
                    Slider(value: $settings.recordDurationSeconds, in: 1...30, step: 1)
                    Text("\(Int(settings.recordDurationSeconds)) seconds")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle("Start camera automatically on launch", isOn: $settings.autoEngageOnLaunch)

            Button("Refresh camera list") { app.refreshCameras() }
        }
        .formStyle(.grouped)
    }

    // MARK: Loop

    private var loop: some View {
        Form {
            Section {
                Toggle("Simulated lag", isOn: $settings.lagEnabled.animation())
                if settings.lagEnabled {
                    Picker("Style", selection: $beta.connectionProfile.animation()) {
                        Text("Stutter").tag(ConnectionProfile.off)
                        Section("Beta") {
                            ForEach(ConnectionProfile.allCases.filter { $0 != .off }) { profile in
                                Text(profile.displayName).tag(profile)
                            }
                        }
                    }
                    if beta.connectionProfile == .off {
                        LabeledContent("Intensity") {
                            VStack(alignment: .leading) {
                                Slider(value: $settings.lagIntensity, in: 0.1...1.0)
                                Text(intensityLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(beta.connectionProfile.summary)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Lifelike loop")
            } footer: {
                Text(lagFooter).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Quality", selection: $settings.outputQuality) {
                    Text("1080p · Sharpest").tag(OutputQuality.fullHD)
                    Text("720p · Softer").tag(OutputQuality.hd)
                }
            } header: {
                Text("Picture")
            } footer: {
                Text("720p softens your picture, live and loop alike, so the loop is even harder to spot. Applies right away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var lagFooter: String {
        let base = "Adds subtle, never-repeating freezes and micro-stutters so the loop reads like a flaky connection rather than a frozen app. The loop itself plays forward-then-backward so it never cuts."
        guard settings.lagEnabled, beta.connectionProfile != .off else { return base }
        return base + " Beta styles also go blocky now and then. A new style applies the next time the loop starts."
    }

    private var intensityLabel: String {
        switch settings.lagIntensity {
        case ..<0.34: return "Subtle"
        case ..<0.67: return "Moderate"
        default: return "Choppy"
        }
    }

    // MARK: Shortcut

    private var shortcut: some View {
        Form {
            Section {
                Toggle("Global shortcut", isOn: $settings.hotkeyEnabled)
                if settings.hotkeyEnabled {
                    Picker("Toggle live / loop", selection: hotkeyBinding) {
                        ForEach(HotkeyPreset.all) { preset in
                            Text(preset.display).tag(preset.id)
                        }
                    }
                }
            } header: {
                Text("Keyboard shortcut")
            } footer: {
                Text("Works system-wide, even while your meeting app is focused — no need to switch windows to step away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyBinding: Binding<String> {
        Binding(
            get: { HotkeyPreset.match(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers).id },
            set: { id in
                if let preset = HotkeyPreset.all.first(where: { $0.id == id }) {
                    settings.hotkeyKeyCode = preset.keyCode
                    settings.hotkeyModifiers = preset.modifiers
                }
            })
    }

    // MARK: Virtual Camera

    private var camera: some View {
        Form {
            Section {
                TextField("Camera name", text: $settings.cameraName)
                Text("Shown in Zoom, Meet, Teams and other apps. Reinstall the camera below to apply a new name.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Appearance")
            }

            Section {
                LabeledContent("Status") {
                    Label(app.extensionInstalled ? "Installed" : "Not installed",
                          systemImage: app.extensionInstalled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(app.extensionInstalled ? .green : .secondary)
                }
                extensionStatusText
                HStack {
                    Button(app.extensionInstalled ? "Reinstall" : "Install") { app.installExtension() }
                    Button("Remove", role: .destructive) { app.removeExtension() }
                        .disabled(!app.extensionInstalled)
                    Spacer()
                    Button("Refresh") { app.refreshExtensionStatus() }
                }
            } header: {
                Text("System extension")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var extensionStatusText: some View {
        switch app.extensionManager.status {
        case .installing:
            Text("Working…").font(.caption).foregroundStyle(.secondary)
        case .needsApproval:
            Text("Approve LiveLoop in System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions.")
                .font(.caption).foregroundStyle(.orange)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}

// MARK: - Hotkey presets

struct HotkeyPreset: Identifiable {
    let id: String
    let display: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotkeyPreset] = {
        let combos: [(String, Int, Int)] = [
            ("⌥⌘L", kVK_ANSI_L, Int(cmdKey | optionKey)),
            ("⌥⌘K", kVK_ANSI_K, Int(cmdKey | optionKey)),
            ("⌃⌥Space", kVK_Space, Int(controlKey | optionKey)),
            ("⌃⌥L", kVK_ANSI_L, Int(controlKey | optionKey)),
            ("⌥⌘P", kVK_ANSI_P, Int(cmdKey | optionKey)),
        ]
        return combos.map { HotkeyPreset(id: $0.0, display: $0.0,
                                         keyCode: UInt32($0.1), modifiers: UInt32($0.2)) }
    }()

    static func match(keyCode: UInt32, modifiers: UInt32) -> HotkeyPreset {
        all.first { $0.keyCode == keyCode && $0.modifiers == modifiers } ?? all[0]
    }
}
