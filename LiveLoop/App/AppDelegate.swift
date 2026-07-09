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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
