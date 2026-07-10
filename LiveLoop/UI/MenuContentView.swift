//
//  MenuContentView.swift
//  LiveLoop
//
//  The menu-bar panel: a live preview of what viewers see, the primary controls
//  (start camera, live⇄loop, record), and the clip library.
//

import SwiftUI
import UniformTypeIdentifiers

struct MenuContentView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let panelWidth: CGFloat = 340
    private let maxVisibleClips = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if app.banner != nil { statusBanner }
            previewCard

            if !app.extensionInstalled {
                installBanner
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if app.isEngaged {
                controls
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
            clipSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: panelWidth)
        .tint(.brand)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: app.banner)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9), value: app.isEngaged)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9), value: app.extensionInstalled)
        .background(WindowAccessor { app.panelWindow = $0 })
        .onAppear {
            app.setPreviewsActive(true)
            app.refreshExtensionStatus()
            app.refreshCameras()
        }
        .onDisappear { app.setPreviewsActive(false) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "repeat")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(brandGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("LiveLoop").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(statusColor)
            }
            Spacer()
            Circle().fill(statusColor).frame(width: 9, height: 9)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: statusColor)
        }
    }

    // MARK: - Status banner

    private var statusBanner: some View {
        HStack(spacing: 8) {
            if let banner = app.banner {
                Image(systemName: bannerIcon(banner.kind))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(bannerColor(banner.kind))
                Text(banner.text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if banner.kind == .working {
                    ProgressView().controlSize(.small)
                } else {
                    Button { app.dismissBanner() } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background((app.banner.map { bannerColor($0.kind) } ?? .clear).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func bannerIcon(_ kind: AppBanner.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        case .working: return "arrow.triangle.2.circlepath"
        }
    }

    private func bannerColor(_ kind: AppBanner.Kind) -> Color {
        switch kind {
        case .success: return .green
        case .failure: return .red
        case .info:    return .brand
        case .working: return .orange
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        ZStack {
            if app.isEngaged {
                CameraPreview(renderer: app.preview)
            } else if let clip = app.currentClip {
                idleLoopReady(url: app.library.url(for: clip), clipName: clip.name)
            } else {
                idleNoClip
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176) // 312pt content width ≈ 16:9
        .background(Color.black)
        .overlay(alignment: .topLeading) { modeBadge.padding(8) }
        .overlay(alignment: .topTrailing) {
            if app.isEngaged, app.isLoopActive { selfViewPIP.padding(8) }
        }
        .overlay(alignment: .bottom) { if app.isEngaged { previewCaption } }
        // Clip AFTER the overlays so their corners follow the rounded card.
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if !app.isEngaged { Task { await app.engage() } }
        }
    }

    /// Camera off but a clip is selected: preview the loop that's ready to play.
    private func idleLoopReady(url: URL, clipName: String) -> some View {
        ZStack {
            ClipBackdropView(url: url)
                .blur(radius: 14)
                .scaleEffect(1.18) // hide blur edge-bleed
            Color.black.opacity(0.45)
            VStack(spacing: 7) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(.white)
                Text("Start camera to go live").font(.subheadline).bold().foregroundStyle(.white)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Label("Loop ready · \(clipName)", systemImage: "repeat")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 8).padding(.vertical, 6)
        }
    }

    /// Camera off and no clip yet: a branded prompt to record one.
    private var idleNoClip: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.16),
                                    Color(red: 0.15, green: 0.11, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
                Text("Record a clip to get started").font(.subheadline).bold().foregroundStyle(.white)
                Text("Then Start Camera and loop it").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    /// Small mirror of your real webcam, so you can see yourself while the loop
    /// plays for viewers.
    private var selfViewPIP: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(renderer: app.livePreview)
            HStack(spacing: 3) {
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("YOU · REAL CAM")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55))
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.6), lineWidth: 1))
        .shadow(radius: 3)
    }

    @ViewBuilder
    private var modeBadge: some View {
        switch app.mode {
        case .loop:
            badge("LOOP", color: .orange, icon: "repeat")
        case .live:
            badge("LIVE", color: .red, icon: "dot.radiowaves.left.and.right")
        case .idle:
            EmptyView()
        }
    }

    private func badge(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4)))
    }

    private var previewCaption: some View {
        HStack {
            Text(app.isLoopActive ? "Viewers see your loop" : "Viewers see your live camera")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear],
                                   startPoint: .bottom, endPoint: .top))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
        Button { app.toggleLoopLive() } label: {
            actionRow(title: app.isLoopActive ? "Switch back to live camera" : "Switch to Loop",
                      subtitle: app.isLoopActive
                        ? "Return to your real webcam"
                        : "Play \(currentClipName) on a seamless loop",
                      systemImage: app.isLoopActive ? "video.fill" : "repeat",
                      tint: app.isLoopActive ? .green : .orange,
                      trailing: AnyView(HotkeyBadge(display: app.settings.hotkeyDisplayString)))
        }
        .buttonStyle(.plain)
        .disabled(!app.isLoopActive && app.currentClip == nil)

        HStack(spacing: 8) {
            Button {
                app.isRecording ? app.stopRecording() : app.startRecording()
            } label: {
                Label(app.isRecording ? "Stop · \(app.recordSecondsLeft)s"
                                      : "Record \(Int(app.settings.recordDurationSeconds))s clip",
                      systemImage: app.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
                    .monospacedDigit()
            }
            .tint(app.isRecording ? .red : nil)

            Button { app.disengage() } label: {
                Label("Stop camera", systemImage: "power").labelStyle(.iconOnly)
            }
            .help("Stop the virtual camera")
            .accessibilityLabel("Stop camera")
        }
        .controlSize(.large)
        }
    }

    private var currentClipName: String { app.currentClip?.name ?? "a clip" }

    private func actionRow(title: String, subtitle: String, systemImage: String,
                           tint: Color, trailing: AnyView? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).bold().foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let trailing { trailing }
        }
        .padding(9)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    // MARK: - Install banner

    private var installBanner: some View {
        Button {
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
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
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clips

    private var clipSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Clips").font(.subheadline).bold()
                if app.library.clips.count > 1 {
                    Text("↑↓")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .help("↑ ↓ browse clips · ⌫ delete · ⌘Z undo")
                }
                Spacer()
                Button(action: importClip) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 13))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Import a clip")
                .accessibilityLabel("Import a clip")
            }

            if app.library.clips.isEmpty {
                Text("Record a short clip of yourself to loop.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(app.library.clips) { clip in
                                ClipRow(clip: clip,
                                        url: app.library.url(for: clip),
                                        isSelected: clip.id == app.selectedClipID,
                                        onSelect: { app.selectClip(clip) },
                                        onRename: { newName in app.library.rename(clip, to: newName) },
                                        onPin: { app.library.setPinned(clip, !clip.pinned) },
                                        onExport: { exportClip(clip) },
                                        onDelete: { app.deleteClip(clip) })
                                    .id(clip.id)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    // Exactly N rows tall (no half-row peeking) — and a definite
                    // height so the ScrollView doesn't collapse in this tall panel.
                    .frame(height: CGFloat(min(app.library.clips.count, maxVisibleClips)) * ClipRow.height)
                    // Keep the arrow-key-selected clip in view.
                    .onChange(of: app.selectedClipID) { _, id in
                        guard let id else { return }
                        if reduceMotion {
                            proxy.scrollTo(id, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 13) {
            Link(destination: Links.github) {
                Image("GitHubMark").renderingMode(.template).resizable().frame(width: 14, height: 14)
            }
            .help("Source on GitHub")
            .accessibilityLabel("Source on GitHub")

            Link(destination: Links.kofi) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 12))
            }
            .help("Support on Ko-fi")
            .accessibilityLabel("Support LiveLoop on Ko-fi")

            Spacer()

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 13))
            }
            .help("Settings")
            .accessibilityLabel("Settings")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
            }
            .help("Quit LiveLoop")
            .accessibilityLabel("Quit LiveLoop")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Status helpers

    private var statusText: String {
        if app.isRecording { return "Recording…" }
        switch app.mode {
        case .loop: return "Looping — you can step away"
        case .live: return "Live camera"
        case .idle: return app.extensionInstalled ? "Camera ready" : "Set up the virtual camera"
        }
    }

    private var statusColor: Color {
        if app.isRecording { return .red }
        switch app.mode {
        case .loop: return .orange
        case .live: return .red
        case .idle: return app.extensionInstalled ? .green : .orange
        }
    }

    private var brandGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1.0),
                                Color(red: 0.55, green: 0.36, blue: 1.0)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Import / export

    private func importClip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                if let clip = await app.library.importClip(from: url) { app.selectClip(clip) }
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
    static let height: CGFloat = 44

    let clip: Clip
    let url: URL
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onPin: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            ClipThumbnailView(url: url)
            VStack(alignment: .leading, spacing: 1) {
                if isEditing {
                    RenameField(text: $editText, onCommit: commit)
                        .frame(height: 17)
                } else {
                    Text(clip.name).font(.subheadline).lineLimit(1)
                        .onTapGesture(count: 2, perform: startEditing)
                }
                Text(String(format: "%.1fs", clip.durationSeconds))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if !isEditing {
                if clip.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
                }
                Menu {
                    Button("Rename…", action: startEditing)
                    Button(clip.pinned ? "Unpin" : "Pin", action: onPin)
                    Button("Export…", action: onExport)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").font(.caption)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 18)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onSelect() } }
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.brand.opacity(0.12) }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }

    private func startEditing() {
        editText = clip.name
        isEditing = true
    }

    private func commit() {
        let name = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != clip.name { onRename(name) }
        isEditing = false
    }
}
