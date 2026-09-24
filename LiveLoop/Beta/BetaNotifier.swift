//
//  BetaNotifier.swift
//  LiveLoop
//
//  Local notifications for the beta features ("still away?", "someone said
//  your name"). Nothing is registered until a feature first needs it.
//

import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.adrbn.LiveLoop", category: "BetaNotifier")

@MainActor
final class BetaNotifier: NSObject {

    private var center: UNUserNotificationCenter { .current() }
    private var isPrepared = false

    func requestPermission() {
        prepare()
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { logger.error("Notification permission failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func post(id: String, title: String, body: String) {
        prepare()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error { logger.error("Couldn't post notification: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        center.delegate = self
    }
}

extension BetaNotifier: UNUserNotificationCenterDelegate {
    /// Show banners even when LiveLoop counts as the active app (its panel is open).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
