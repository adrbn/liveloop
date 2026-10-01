//
//  PreviewWindowView.swift
//  LiveLoop
//
//  A bigger preview that floats over your call: what viewers see and your
//  real camera, side by side or one over the other, so you can line yourself
//  up with the loop before switching back. Resizable; fed only while open.
//

import SwiftUI

struct PreviewWindowView: View {

    static let windowID = "preview"

    @EnvironmentObject private var app: AppState
    @AppStorage("previewWindowLayout") private var storedLayout = PreviewWindowLayout.sideBySide.rawValue

    private var layout: PreviewWindowLayout { PreviewWindowLayout(storedValue: storedLayout) }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            if app.isEngaged {
                pictures
            } else {
                cameraOff
            }
        }
        .padding(12)
        .frame(minWidth: 420, minHeight: 200)
        .background(WindowAccessor { window in
            // Stay above the meeting window, on every Space.
            window?.level = .floating
            window?.collectionBehavior.insert(.canJoinAllSpaces)
        })
        .onAppear { app.setWindowPreviewsActive(true) }
        .onDisappear { app.setWindowPreviewsActive(false) }
    }

    private var toolbar: some View {
        HStack {
            Picker("Layout", selection: $storedLayout) {
                ForEach(PreviewWindowLayout.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            if app.isEngaged {
                Button(app.isLoopActive ? "Back to live" : "Switch to Loop") { app.toggleLoopLive() }
                    .disabled(!app.isLoopActive && app.currentClip == nil)
            }
        }
    }

    @ViewBuilder
    private var pictures: some View {
        switch layout {
        case .sideBySide:
            HStack(spacing: 10) {
                pane(CameraPreview(renderer: app.windowPreview), label: viewersLabel)
                pane(CameraPreview(renderer: app.windowLivePreview), label: "You · real camera")
            }
        case .overlay:
            pane(ZStack {
                CameraPreview(renderer: app.windowPreview)
                CameraPreview(renderer: app.windowLivePreview, opacity: layout.liveOpacity)
            }, label: app.isLoopActive ? "Line yourself up with the loop" : "Viewers see your live camera")
        }
    }

    private var viewersLabel: String {
        app.isLoopActive ? "Viewers see your loop" : "Viewers see your live camera"
    }

    private func pane(_ content: some View, label: String) -> some View {
        content
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)
            .overlay(alignment: .bottomLeading) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cameraOff: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("The camera is off").font(.headline)
            Button("Start the camera") { Task { await app.engage() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
