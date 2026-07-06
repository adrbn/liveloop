//
//  MenuContentView.swift
//  LiveLoop
//
//  The menu-bar panel: the primary controls (start camera, live⇄loop, record)
//  and the clip library.
//

import SwiftUI
import UniformTypeIdentifiers

struct MenuContentView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !app.extensionInstalled {
                installBanner
            }

            primaryControls

            Divider()

            clipSection

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { app.refreshExtensionStatus(); app.refreshCameras() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "repeat")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1.0),
                                                    Color(red: 0.55, green: 0.36, blue: 1.0)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("LiveLoop").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
        }
    }

    private var statusText: String {
        if app.isRecording { return "Recording…" }
        switch app.mode {
        case .loop: return "Looping — you can step away"
        case .live: return "Live camera"
        case .idle: return app.extensionInstalled ? "Ready" : "Set up the virtual camera"
        }
    }

    private var statusColor: Color {
        if app.isRecording { return .red }
        switch app.mode {
        case .loop: return .orange
        case .live: return .green
        case .idle: return .secondary
        }
    }

    // MARK: - Install banner

    private var installBanner: some View {
        Button {
            openWindow(id: "onboarding")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Virtual camera not installed").font(.subheadline).bold()
                    Text("Click to set up LiveLoop").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary controls

    private var primaryControls: some View {
        VStack(spacing: 8) {
            if !app.isEngaged {
                Button {
                    Task { await app.engage() }
                } label: {
                    controlLabel(title: "Start Camera",
                                 subtitle: "Begin feeding the virtual camera",
                                 systemImage: "play.fill",
                                 tint: .accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    app.toggleLoopLive()
                } label: {
                    controlLabel(title: app.isLoopActive ? "Back to Live" : "Switch to Loop",
                                 subtitle: app.isLoopActive
                                    ? "Return to your real webcam"
                                    : "Play \(currentClipName) on a seamless loop",
                                 systemImage: app.isLoopActive ? "video.fill" : "repeat",
                                 tint: app.isLoopActive ? .green : .orange)
                }
                .buttonStyle(.plain)
                .disabled(!app.isLoopActive && app.currentClip == nil)

                HStack(spacing: 8) {
                    Button {
                        app.isRecording ? app.stopRecording() : app.startRecording()
                    } label: {
                        Label(app.isRecording ? "Stop" : "Record \(Int(app.settings.recordDurationSeconds))s clip",
                              systemImage: app.isRecording ? "stop.fill" : "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(app.isRecording ? .red : nil)

                    Button {
                        app.disengage()
                    } label: {
                        Label("Stop", systemImage: "pause.fill").labelStyle(.iconOnly)
                    }
                    .help("Stop the virtual camera")
                }
                .controlSize(.large)

                if !app.extensionInstalled {
                    Text("Install the virtual camera to be seen in Zoom, Meet, Teams…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("Shortcut: \(app.settings.hotkeyDisplayString) toggles live/loop")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var currentClipName: String {
        app.currentClip?.name ?? "a clip"
    }

    private func controlLabel(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).bold().foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Clips

    private var clipSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clips").font(.subheadline).bold()
                Spacer()
                Button(action: importClip) {
                    Label("Import", systemImage: "square.and.arrow.down").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }

            if app.library.clips.isEmpty {
                Text("Record a short clip of yourself to loop.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(app.library.clips) { clip in
                            ClipRow(clip: clip,
                                    isSelected: clip.id == app.selectedClipID,
                                    onSelect: { app.selectClip(clip) },
                                    onPin: { app.library.setPinned(clip, !clip.pinned) },
                                    onExport: { exportClip(clip) },
                                    onDelete: { app.library.delete(clip) })
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    // MARK: - Import / export

    private func importClip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                if let clip = await app.library.importClip(from: url) {
                    app.selectClip(clip)
                }
            }
        }
    }

    private func exportClip(_ clip: Clip) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(clip.name).mov"
        panel.allowedContentTypes = [.quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url {
            try? app.library.export(clip, to: url)
        }
    }
}

// MARK: - Clip row

private struct ClipRow: View {
    let clip: Clip
    let isSelected: Bool
    let onSelect: () -> Void
    let onPin: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(clip.name).font(.subheadline).lineLimit(1)
                Text(String(format: "%.1fs", clip.durationSeconds))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if clip.pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
            }
            Menu {
                Button(clip.pinned ? "Unpin" : "Pin", action: onPin)
                Button("Export…", action: onExport)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis").font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 24)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.10) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
