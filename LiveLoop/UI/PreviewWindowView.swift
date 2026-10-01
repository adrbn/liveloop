//
//  PreviewWindowView.swift
//  LiveLoop
//
//  A bigger preview that floats over your call: what viewers see and your
//  real camera, side by side or one over the other, so you can line yourself
//  up with the loop before switching back. Dark and edge to edge, like a video
//  player; the controls sit in the title bar. Fed only while on screen.
//

import SwiftUI

struct PreviewWindowView: View {

    static let windowID = "preview"

    @EnvironmentObject private var app: AppState
    @AppStorage("previewWindowLayout") private var storedLayout = PreviewWindowLayout.sideBySide.rawValue

    private var layout: PreviewWindowLayout { PreviewWindowLayout(storedValue: storedLayout) }

    /// Height of the title-bar strip the controls share with the window buttons.
    private let titleBarHeight: CGFloat = 32
    private let gap: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Group {
                if app.isEngaged { pictures } else { cameraOff }
            }
            .padding([.horizontal, .bottom], gap)
        }
        .frame(minWidth: 460, minHeight: 190)
        .background(Color.black)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .tint(.brand)
        .background(WindowAccessor { window in
            guard let window else { return }
            // Stay above the meeting window, on every Space.
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
        })
        // Feed only while actually on screen: minimised or hidden, the layers
        // never drain (see `PreviewRenderer`). Closing the window disappears it.
        .background(WindowVisibilityObserver { app.setWindowPreviewsActive($0) })
        .onDisappear { app.setWindowPreviewsActive(false) }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Spacer()
            Picker("Layout", selection: $storedLayout) {
                ForEach(PreviewWindowLayout.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if app.isEngaged {
                Button { app.toggleLoopLive() } label: {
                    Label(app.isLoopActive ? "Back to live" : "Switch to Loop",
                          systemImage: app.isLoopActive ? "video.fill" : "repeat")
                }
                .disabled(!app.isLoopActive && app.currentClip == nil)
            }
        }
        .controlSize(.small)
        .padding(.leading, 80) // clear of the window buttons
        .padding(.trailing, 10)
        .frame(height: titleBarHeight)
    }

    // MARK: - Pictures

    @ViewBuilder
    private var pictures: some View {
        switch layout {
        case .sideBySide:
            HStack(spacing: gap) {
                pane(CameraPreview(renderer: app.windowPreview), badge: modeBadge, caption: viewersCaption)
                pane(CameraPreview(renderer: app.windowLivePreview),
                     badge: badge("YOU", color: .green), caption: "Real camera · only you see this")
            }
        case .overlay:
            pane(ZStack {
                CameraPreview(renderer: app.windowPreview)
                CameraPreview(renderer: app.windowLivePreview, opacity: layout.liveOpacity)
            }, badge: modeBadge, caption: app.isLoopActive
                ? "Line yourself up with the loop, then switch back"
                : "Your camera over what viewers see")
        }
    }

    private var viewersCaption: String {
        app.isLoopActive ? "Viewers see your loop" : "Viewers see your live camera"
    }

    private var modeBadge: some View {
        app.isLoopActive ? badge("LOOP", color: .orange) : badge("LIVE", color: .red)
    }

    private func badge(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4)))
    }

    private func pane(_ content: some View, badge: some View, caption: String) -> some View {
        content
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topLeading) { badge.padding(8) }
            .overlay(alignment: .bottom) {
                HStack {
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(LinearGradient(colors: [.black.opacity(0.55), .clear],
                                           startPoint: .bottom, endPoint: .top))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cameraOff: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash").font(.system(size: 26)).foregroundStyle(.white.opacity(0.5))
            Text("The camera is off").font(.headline).foregroundStyle(.white)
            Button("Start the camera") { Task { await app.engage() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Reports whether its window is visible on screen, including after it's
/// minimised, restored, moved to another Space or fully covered.
private struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObservingView { ObservingView(onChange: onChange) }
    func updateNSView(_ nsView: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        private let onChange: (Bool) -> Void
        private var observer: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.report() }
            report()
        }

        private func report() {
            onChange(window?.occlusionState.contains(.visible) ?? false)
        }

        deinit { observer.map(NotificationCenter.default.removeObserver) }
    }
}
