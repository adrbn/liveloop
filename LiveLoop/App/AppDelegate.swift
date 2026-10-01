//
//  AppDelegate.swift
//  LiveLoop
//
//  Keeps LiveLoop feeling like a menu-bar app: once camera permission is
//  settled, drop the Dock icon. On first run (permission undetermined) the app
//  stays a regular app so the camera permission prompt can actually appear — a
//  pure background (LSUIElement) app can't present it.
//

import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Opens the setup window. Set once SwiftUI is up (see `MenuBarLabel`).
    var showSetup: (() -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Beta automations: take `liveloop://` links ourselves (registered before
        // launch completes so a link that launched the app isn't lost). Handling
        // the Apple Event directly keeps SwiftUI from opening a window for it.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Clicking the Dock icon shows setup: the menu-bar icon can be out of
    /// sight (behind the notch, or hidden in System Settings ▸ Menu Bar).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSetup?() }
        return true
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        AutomationCenter.shared.open(url)
    }
}
