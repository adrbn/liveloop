//
//  OnboardingView.swift
//  LiveLoop
//
//  First-run flow that installs and activates the camera system extension.
//

import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 14) {
                step(number: 1,
                     title: "Install the virtual camera",
                     detail: "LiveLoop adds a camera called “\(app.settings.cameraName)” that Zoom, Meet, Teams, FaceTime and OBS can select.",
                     content: AnyView(installControls))

                step(number: 2,
                     title: "Approve it in System Settings",
                     detail: "macOS asks you to allow the extension the first time. Open System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions and enable LiveLoop.",
                     content: AnyView(
                        Button("Open System Settings") { openExtensionSettings() }
                     ))

                step(number: 3,
                     title: "Pick LiveLoop as your camera",
                     detail: "In your meeting app’s camera menu, choose “\(app.settings.cameraName)”. Use Start Camera in the menu bar, then the shortcut to step away.",
                     content: AnyView(EmptyView()))
            }

            if isSelfSignedNote {
                selfSignedNote
            }

            Divider()

            HStack {
                statusView
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { app.refreshExtensionStatus() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1.0),
                                                    Color(red: 0.55, green: 0.36, blue: 1.0)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading) {
                Text("Set up LiveLoop").font(.title2).bold()
                Text("Step away, stay on camera.").foregroundStyle(.secondary)
            }
        }
    }

    private func step(number: Int, title: String, detail: String, content: AnyView) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline).bold()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                content
            }
        }
    }

    private var installControls: some View {
        HStack {
            Button(app.extensionInstalled ? "Reinstall Camera" : "Install Camera") {
                app.installExtension()
            }
            .disabled(app.extensionManager.status == .installing)
            if app.extensionManager.status == .installing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var statusView: some View {
        Label(app.extensionInstalled ? "Virtual camera ready" : "Not installed yet",
              systemImage: app.extensionInstalled ? "checkmark.circle.fill" : "circle.dashed")
            .font(.subheadline)
            .foregroundStyle(app.extensionInstalled ? .green : .secondary)
    }

    private var isSelfSignedNote: Bool {
        if case .failed = app.extensionManager.status { return true }
        return app.extensionManager.status == .needsApproval
    }

    private var selfSignedNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Developer build", systemImage: "hammer")
                .font(.subheadline).bold()
            Text("This is a self-signed build. If activation is blocked, enable system-extension developer mode once in Terminal, then reinstall:")
                .font(.caption).foregroundStyle(.secondary)
            Text("systemextensionsctl developer on")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func openExtensionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
