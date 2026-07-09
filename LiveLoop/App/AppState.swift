//
//  AppState.swift
//  LiveLoop
//
//  The coordinator that wires the camera, loop engine, router, recorder,
//  library, extension, hotkey and settings together and exposes a small,
//  observable surface for the SwiftUI menu.
//

import Foundation
import Combine
import AppKit
import AVFoundation
import CoreMedia
import CoreVideo

struct CameraOption: Identifiable, Hashable {
    let id: String   // AVCaptureDevice.uniqueID
    let name: String
}

@MainActor
final class AppState: ObservableObject {

    // Sub-systems the UI observes directly.
    let settings = Settings()
    let library = ClipLibrary()
    let extensionManager = ExtensionManager()

    // Observable UI state.
    @Published private(set) var isEngaged = false
    @Published private(set) var mode: FrameRouter.Mode = .idle
    @Published private(set) var isRecording = false
    @Published private(set) var sinkConnected = false
    @Published private(set) var extensionInstalled = false
    @Published private(set) var cameras: [CameraOption] = []
    @Published var selectedClipID: UUID?
    @Published private(set) var loadingClip = false

    /// Mirror of what the virtual camera is broadcasting (for the in-app preview).
    let preview = PreviewRenderer()
    /// Mirror of the real webcam — a self-view, useful while looping.
    let livePreview = PreviewRenderer()

    // Engine.
    private let processingQueue = DispatchQueue(label: "com.adrbn.LiveLoop.processing", qos: .userInteractive)
    private let pipeline = ImagePipeline()
    private let publisher = SinkStreamPublisher()
    private let camera: CameraCaptureManager
    private let loopEngine: LoopEngine
    private let router: FrameRouter
    private let recorder: ClipRecorder
    private let hotkeys = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?

    var isLoopActive: Bool { mode == .loop }

    init() {
        camera = CameraCaptureManager(queue: processingQueue)
        loopEngine = LoopEngine(pipeline: pipeline, queue: processingQueue)
        router = FrameRouter(pipeline: pipeline, publisher: publisher, queue: processingQueue)
        recorder = ClipRecorder(queue: processingQueue)

        router.loopEngine = loopEngine
        router.onModeChange = { [weak self] mode in self?.mode = mode }

        // Mirror every emitted frame into the in-app preview.
        let preview = self.preview
        router.onOutputFrame = { buffer in
            DispatchQueue.main.async { preview.enqueue(buffer) }
        }

        // Fan every captured frame out to the router, recorder, and self-view.
        let livePreview = self.livePreview
        camera.onSampleBuffer = { [router, recorder] sampleBuffer in
            router.handleLiveFrame(sampleBuffer)
            recorder.append(sampleBuffer)
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                DispatchQueue.main.async { livePreview.enqueue(pixelBuffer) }
            }
        }

        applyLagSettings()
        observeSettings()
        observeExtensionStatus()
        refreshCameras()
        registerHotkey()

        selectedClipID = library.clips.first?.id
        refreshExtensionStatus()
        installClipKeyMonitor()
    }

    /// Delete the selected clip on Backspace / Forward-delete — but never while a
    /// text field (e.g. inline rename) is being edited.
    private func installClipKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 51 || event.keyCode == 117 else { return event }
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSText || responder is NSTextView {
                return event
            }
            guard let clip = self.currentClip else { return event }
            self.library.delete(clip)
            self.selectedClipID = self.library.clips.first?.id
            return nil
        }
    }

    // MARK: - Extension status

    func refreshExtensionStatus() {
        extensionInstalled = SinkStreamPublisher.deviceIsAvailable()
    }

    private func observeExtensionStatus() {
        extensionManager.$status
            .sink { [weak self] status in
                guard let self else { return }
                if status == .installed {
                    // The device appears a moment after activation completes.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.refreshExtensionStatus()
                        if self.isEngaged { self.reconnectSink() }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Engagement

    func engage() async {
        guard !isEngaged else { return }
        guard await requestCameraAccess() else { return }
        reconnectSink()
        camera.start(deviceID: settings.selectedCameraID)
        router.engageLive()
        isEngaged = true
    }

    func disengage() {
        guard isEngaged else { return }
        router.disengage()
        camera.stop()
        publisher.disconnect()
        isEngaged = false
        sinkConnected = false
    }

    /// (Re)connects to the extension's sink stream. Safe to call repeatedly.
    @discardableResult
    func reconnectSink() -> Bool {
        let state = publisher.connect()
        sinkConnected = (state == .connected)
        return sinkConnected
    }

    // MARK: - Live / loop

    func toggleLoopLive() {
        Task {
            if !isEngaged { await engage() }
            if mode == .loop {
                router.goToLive()
            } else {
                await goToLoop()
            }
        }
    }

    func goToLoop() async {
        if !loopEngine.isLoaded {
            guard let clip = currentClip ?? library.clips.first else { return }
            await loadClip(clip)
        }
        guard loopEngine.isLoaded else { return }
        applyLagSettings()
        router.goToLoop()
    }

    func goToLive() {
        router.goToLive()
    }

    // MARK: - Clips

    var currentClip: Clip? {
        guard let id = selectedClipID else { return nil }
        return library.clips.first { $0.id == id }
    }

    func selectClip(_ clip: Clip) {
        selectedClipID = clip.id
        Task { await loadClip(clip) }
    }

    private func loadClip(_ clip: Clip) async {
        loadingClip = true
        defer { loadingClip = false }
        let url = library.url(for: clip)
        if let store = await ClipFrameLoader.load(url: url, pipeline: pipeline) {
            loopEngine.load(store)
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        Task {
            guard await requestCameraAccess() else { return }
            if !camera.isRunning { camera.start(deviceID: settings.selectedCameraID) }
            isRecording = true
            recorder.start(maxDuration: max(1, settings.recordDurationSeconds)) { [weak self] url, duration in
                self?.finishRecording(url: url, duration: duration)
            }
            // Auto-stop at the chosen length.
            let target = max(1, settings.recordDurationSeconds)
            try? await Task.sleep(nanoseconds: UInt64(target * 1_000_000_000))
            if self.isRecording { self.recorder.stop() }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder.stop()
    }

    private func finishRecording(url: URL?, duration: Double) {
        isRecording = false
        guard let url else { return }
        let name = "Clip \(library.clips.count + 1)"
        if let clip = library.add(movingFileAt: url, name: name, duration: duration) {
            selectClip(clip)
        }
    }

    // MARK: - Extension

    func installExtension() {
        extensionManager.install()
    }

    // MARK: - Cameras

    func refreshCameras() {
        cameras = CameraCaptureManager.availableCameras().map {
            CameraOption(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    func selectCamera(_ id: String?) {
        settings.selectedCameraID = id
        if isEngaged { camera.start(deviceID: id) }
    }

    // MARK: - Private

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            // A menu-bar-only (accessory) app can't reliably present the TCC
            // prompt. Become a regular foreground app, let the activation land,
            // then request so the prompt appears on top.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            NSApp.setActivationPolicy(.accessory)
            return granted
        default:
            return false
        }
    }

    private func applyLagSettings() {
        loopEngine.lagEnabled = settings.lagEnabled
        loopEngine.lagIntensity = settings.lagIntensity
    }

    private func registerHotkey() {
        hotkeys.onTrigger = { [weak self] in self?.toggleLoopLive() }
        if settings.hotkeyEnabled {
            hotkeys.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
        }
    }

    private func observeSettings() {
        settings.$lagEnabled
            .combineLatest(settings.$lagIntensity)
            .sink { [weak self] _ in self?.applyLagSettings() }
            .store(in: &cancellables)

        settings.$hotkeyEnabled
            .combineLatest(settings.$hotkeyKeyCode, settings.$hotkeyModifiers)
            .sink { [weak self] enabled, keyCode, modifiers in
                guard let self else { return }
                self.hotkeys.unregister()
                if enabled {
                    self.hotkeys.register(keyCode: keyCode, modifiers: modifiers)
                }
            }
            .store(in: &cancellables)
    }
}
