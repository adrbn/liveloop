//
//  BetaSettingsView.swift
//  LiveLoop
//
//  Settings ▸ Beta. Experimental features, all off by default, grouped by
//  what you're trying to do. Each is one row — icon, what it does, a switch —
//  and its options and privacy details only appear once it's on.
//

import SwiftUI

struct BetaSettingsView: View {
    @ObservedObject var settings: BetaSettings
    let controller: BetaController
    let clipNames: [String]

    private static let awayChoices: [Double] = [5, 10, 20, 30]
    private static let reminderChoices = [0, 5, 10, 15, 30]

    var body: some View {
        Form {
            header
            whileAway
            lookNatural
            BetaNameAlertSection(settings: settings, controller: controller)
            BetaAutomationSection(settings: settings, clipNames: clipNames)
        }
        .formStyle(.grouped)
    }

    // MARK: Sections

    private var header: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                FeatureIcon(symbol: "flask", tint: .indigo, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Beta Features").font(.headline)
                    Text("New ideas to try early. Each one stays off until you turn it on, and all of them run entirely on this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var whileAway: some View {
        Section {
            Toggle(isOn: $settings.autoAwayEnabled.animation()) {
                FeatureLabel(title: "Auto away",
                             subtitle: "Switches to your loop when you leave your desk.",
                             symbol: "figure.walk.departure", tint: .orange)
            }
            if settings.autoAwayEnabled {
                Picker("Switch after", selection: $settings.autoAwaySeconds) {
                    ForEach(Self.awayChoices, id: \.self) { seconds in
                        Text("\(Int(seconds)) seconds away").tag(seconds)
                    }
                }
                .padding(.leading, FeatureLabel.optionInset)
                Toggle("Go live again when you're back", isOn: $settings.autoReturnEnabled)
                    .padding(.leading, FeatureLabel.optionInset)
            }

            Picker(selection: $settings.reminderMinutes) {
                ForEach(Self.reminderChoices, id: \.self) { minutes in
                    Text(minutes == 0 ? "Never" : "Every \(minutes) min").tag(minutes)
                }
            } label: {
                FeatureLabel(title: "Away reminder",
                             subtitle: "A notification while you're still on the loop.",
                             symbol: "bell.badge", tint: .red)
            }
            .onChange(of: settings.reminderMinutes) { _, minutes in
                if minutes > 0 { controller.requestNotificationPermission() }
            }

            Toggle(isOn: $settings.loopTimerEnabled) {
                FeatureLabel(title: "Loop timer",
                             subtitle: "Shows how long you've been away, in the menu bar.",
                             symbol: "timer", tint: .blue)
            }
        } header: {
            Text("While You're Away")
        } footer: {
            if settings.autoAwayEnabled {
                caption("Auto away checks your camera for a face a few times a second, with on-device Vision. Frames are never saved. It only ends loops it started.")
            }
        }
    }

    private var lookNatural: some View {
        Section {
            Toggle(isOn: $settings.smartSwitchEnabled.animation()) {
                FeatureLabel(title: "Smart switch",
                             subtitle: "Matches your pose, so the cut to and from the loop is hard to spot.",
                             symbol: "person.crop.rectangle.stack", tint: .purple)
            }
        } header: {
            Text("Look Natural")
        } footer: {
            caption(lookNaturalFooter)
        }
    }

    // MARK: Helpers

    private var lookNaturalFooter: String {
        let styles = "The connection styles (Shaky Wi-Fi, 4G, Dropping out) are under Loop ▸ Simulated lag."
        guard settings.smartSwitchEnabled else { return styles }
        return "Going live can wait up to 2 seconds for the loop to line up with you. " + styles
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
