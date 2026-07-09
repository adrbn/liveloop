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
import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import CoreVideo

struct CameraOption: Identifiable, Hashable {
    let id: String   // AVCaptureDevice.uniqueID
    let name: String
}

/// A transient, user-facing status line so every meaningful action reports its
/// outcome instead of succeeding or failing silently.
struct AppBanner: Equatable {
    enum Kind { case success, failure, info, working }
    let kind: Kind
    let text: String
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
    private var loadedClipID: UUID?
    /// Set once the OS confirms activation — trusted over CMIO device discovery,
    /// which can lag inside a long-running process.
    private var osConfirmedInstalled = false
    /// Clips deleted this session, most-recent last — the ⌘Z undo stack.
    private var deletionUndoStack: [Clip] = []
    /// True when the current engagement was started automatically because a
    /// meeting app opened the virtual camera — so it can be torn down when the
    /// last consumer leaves, without disturbing a session the user started by hand.
    private var engagedOnDemand = false
    private var onDemandDisengageTask: Task<Void, Never>?

    /// The menu-bar panel's hosting window (captured when it appears), used to
    /// scope global key shortcuts to the panel and away from Settings.
    weak var panelWindow: NSWindow?

    /// Seconds left in the current recording (for the live countdown).
    @Published private(set) var recordSecondsLeft = 0

    /// The current user-facing status banner (nil when nothing to report).
    @Published private(set) var banner: AppBanner?
    private var bannerDismiss: Task<Void, Never>?

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
        // Re-publish nested library changes so views observing AppState re-render
        // (and animate) when clips are added, deleted, or restored.
        library.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        observeExtensionStatus()
        refreshCameras()
        registerHotkey()

        selectedClipID = library.clips.first?.id
        refreshExtensionStatus()
        // Keep "installed?" live: the virtual camera can appear/disappear while
        // the app runs (install, reinstall, replace) — never cache it once.
        SinkStreamPublisher.observeDeviceChanges { [weak self] in
            Task { @MainActor in self?.refreshExtensionStatus() }
        }
        installClipKeyMonitor()
        observeConsumerSignals()
    }

    /// Keyboard shortcuts inside the open panel: ↑/↓ move between clips,
    /// Backspace / Forward-delete removes the selected one. Only active while the
    /// panel is open and never while a text field (inline rename) is being edited.
    private func installClipKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.shortcutsActive else { return event }
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSText || responder is NSTextView {
                return event
            }
            // ⌘Z → undo the last delete. Match the *character*, not the keycode,
            // so it works on any keyboard layout (on AZERTY the "z" key isn't the
            // ANSI-Z keycode). ⌘⇧Z (redo) is intentionally left alone.
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                guard !self.deletionUndoStack.isEmpty else { return event }
                self.undoDelete()
                return nil
            }
            switch event.keyCode {
            case 126: self.navigateClip(-1); return nil   // up arrow
            case 125: self.navigateClip(1);  return nil   // down arrow
            case 51, 117:                                 // delete / forward-delete
                guard let clip = self.currentClip else { return event }
                self.deleteClip(clip)
                return nil
            default:
                return event
            }
        }
    }

    /// Key shortcuts (↑↓, ⌫, ⌘Z) fire only when the panel is the focused surface —
    /// not while Settings or onboarding is up. A non-activating panel leaves the
    /// app with no key window, which we also treat as "the panel".
    private var shortcutsActive: Bool {
        let key = NSApp.keyWindow
        return key == nil || key === panelWindow
    }

    /// Move the selection up (delta -1) or down (delta +1) through the clip list.
    private func navigateClip(_ delta: Int) {
        let clips = library.clips
        guard !clips.isEmpty else { return }
        let current = clips.firstIndex { $0.id == selectedClipID } ?? (delta > 0 ? -1 : 0)
        let next = max(0, min(clips.count - 1, current + delta))
        selectedClipID = clips[next].id
    }

    /// Delete a clip with a leftward swipe-out, pushing it onto the ⌘Z undo stack.
    func deleteClip(_ clip: Clip) {
        let wasSelected = clip.id == selectedClipID
        deletionUndoStack.append(clip)
        animate { self.library.delete(clip) }
        if wasSelected { selectedClipID = library.clips.first?.id }
    }

    /// Undo the most recent deletion (⌘Z): slide the clip back in and select it.
    func undoDelete() {
        guard let clip = deletionUndoStack.popLast() else { return }
        var restored = false
        animate { restored = self.library.restore(clip) }
        if restored { selectedClipID = clip.id }
    }

    /// Run a state change inside an animation, honoring Reduce Motion.
    private func animate(_ changes: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            changes()
        } else {
            // A spring eases in gently (unlike ease-out, which starts at full
            // speed), so the rows below a deleted clip don't snap up and overlap.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9), changes)
        }
    }

    // MARK: - Extension status

    func refreshExtensionStatus() {
        // Trust, in order: the OS's own "activated" confirmation, a live sink
        // connection, then CMIO discovery (which can be stale in-process).
        extensionInstalled = osConfirmedInstalled
            || sinkConnected
            || SinkStreamPublisher.deviceIsAvailable()
    }

    private func observeExtensionStatus() {
        extensionManager.$status
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .needsApproval:
                    self.notify(.info, "Approve LiveLoop in System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions.", sticky: true)
                case .installed:
                    // The OS confirmed activation — trust it immediately.
                    self.osConfirmedInstalled = true
                    self.extensionInstalled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.isEngaged { self.reconnectSink() }
                    }
                    self.notify(.success, "Virtual camera ready ✓")
                case .removed:
                    self.osConfirmedInstalled = false
                    self.extensionInstalled = false
                    self.notify(.info, "Virtual camera removed.")
                case .failed(let message):
                    self.notify(.failure, "Couldn’t set up the camera — \(message)", sticky: true)
                case .installing, .unknown:
                    break   // `installExtension`/`removeExtension` show the "working" banner
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Status banner

    /// Report an outcome to the user. Non-sticky banners fade after a few
    /// seconds; sticky ones (failures, "needs approval") stay until replaced.
    func notify(_ kind: AppBanner.Kind, _ text: String, sticky: Bool = false) {
        banner = AppBanner(kind: kind, text: text)
        bannerDismiss?.cancel()
        guard !sticky else { return }
        bannerDismiss = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.banner = nil }
        }
    }

    func dismissBanner() {
        bannerDismiss?.cancel()
        banner = nil
    }

    // MARK: - Engagement

    func engage(onDemand: Bool = false) async {
        guard !isEngaged else { return }
        guard await requestCameraAccess() else {
            if !onDemand {
                notify(.failure, "Camera access denied — enable it in System Settings ▸ Privacy & Security ▸ Camera.", sticky: true)
            }
            return
        }
        engagedOnDemand = onDemand
        reconnectSink()
        camera.start(deviceID: settings.selectedCameraID)
        router.engageLive()
        isEngaged = true
        if onDemand {
            notify(.info, "Camera on — an app opened LiveLoop.")
        } else {
            notify(.success, "Camera on — you're live.")
        }
    }

    func disengage() {
        guard isEngaged else { return }
        onDemandDisengageTask?.cancel()
        onDemandDisengageTask = nil
        engagedOnDemand = false
        router.disengage()
        camera.stop()
        publisher.disconnect()
        isEngaged = false
        sinkConnected = false
        notify(.info, "Camera off.")
    }

    // MARK: - Engage on demand

    /// Bridges the extension's Darwin notifications to the app: the webcam comes
    /// up when a meeting app opens LiveLoop and goes back down when the last one
    /// leaves — so the camera light is only on while something is watching.
    private func observeConsumerSignals() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let app = Unmanaged<AppState>.fromOpaque(observer).takeUnretainedValue()
            let active = (name.rawValue as String) == LiveLoop.ConsumerSignal.active
            Task { @MainActor in app.consumerDidChange(active: active) }
        }
        for signal in [LiveLoop.ConsumerSignal.active, LiveLoop.ConsumerSignal.inactive] {
            CFNotificationCenterAddObserver(center, observer, callback,
                                            signal as CFString, nil, .deliverImmediately)
        }
    }

    func consumerDidChange(active: Bool) {
        if active {
            onDemandDisengageTask?.cancel()
            onDemandDisengageTask = nil
            Task { await engageOnDemand() }
        } else {
            scheduleOnDemandDisengage()
        }
    }

    private func engageOnDemand() async {
        guard !isEngaged else { return }
        // Never provoke a permission prompt from the background — only auto-engage
        // once the user has already granted camera access.
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        await engage(onDemand: true)
    }

    private func scheduleOnDemandDisengage() {
        guard engagedOnDemand else { return }   // never tear down a manual session
        onDemandDisengageTask?.cancel()
        onDemandDisengageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)   // brief grace for reconnects
            guard let self, !Task.isCancelled else { return }
            if self.engagedOnDemand { self.disengage() }
        }
    }

    /// (Re)connects to the extension's sink stream. Safe to call repeatedly.
    @discardableResult
    func reconnectSink() -> Bool {
        let state = publisher.connect()
        sinkConnected = (state == .connected)
        // Connecting to the sink is proof the extension is installed and live.
        if sinkConnected { extensionInstalled = true }
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
        guard let clip = currentClip ?? library.clips.first else { return }
        // Ensure the *currently selected* clip is what's loaded (arrow-navigating
        // changes the selection without eagerly decoding each clip's frames).
        if !loopEngine.isLoaded || loadedClipID != clip.id {
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
            loadedClipID = clip.id
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        Task {
            guard await requestCameraAccess() else { return }
            if !camera.isRunning { camera.start(deviceID: settings.selectedCameraID) }
            let target = max(1, settings.recordDurationSeconds)
            isRecording = true
            recordSecondsLeft = Int(target.rounded())
            recorder.start(maxDuration: target) { [weak self] url, duration in
                self?.finishRecording(url: url, duration: duration)
            }
            // Tick the countdown down to zero, then auto-stop at the chosen length.
            while isRecording && recordSecondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if isRecording { recordSecondsLeft -= 1 }
            }
            if isRecording { recorder.stop() }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder.stop()
    }

    private func finishRecording(url: URL?, duration: Double) {
        isRecording = false
        recordSecondsLeft = 0
        guard let url else { return }
        let name = "Clip \(library.clips.count + 1)"
        if let clip = library.add(movingFileAt: url, name: name, duration: duration) {
            selectClip(clip)
        }
    }

    // MARK: - Extension

    func installExtension() {
        notify(.working, "Setting up the virtual camera…", sticky: true)
        extensionManager.install()
    }

    func removeExtension() {
        notify(.working, "Removing the virtual camera…", sticky: true)
        extensionManager.uninstall()
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
