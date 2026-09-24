//
//  NameAlertPermissions.swift
//  LiveLoop
//
//  Beta (name alert) — asks for Speech Recognition (and the microphone, if
//  that's the source) when you switch the feature on, rather than the first
//  time you loop in the middle of a meeting, and says plainly when one has
//  been turned off.
//

import Foundation
import AVFoundation
import Speech

enum NameAlertPermissions {

    struct Problem: Equatable {
        let message: String
        /// Where to fix it, when System Settings has a page for it.
        let settingsURL: URL?
    }

    /// Asks for whatever `source` needs that hasn't been decided yet.
    static func request(for source: NameAlertSource) async {
        _ = await NameAlertListener.requestSpeechPermission()
        if source == .microphone {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    /// What would stop name alert from listening to `source` right now, if anything.
    static func problem(for source: NameAlertSource) -> Problem? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            return Problem(message: "Speech Recognition is turned off for LiveLoop.",
                           settingsURL: privacyPane("Privacy_SpeechRecognition"))
        default:
            break
        }
        switch source {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .denied, .restricted:
                return Problem(message: "Microphone access is turned off for LiveLoop.",
                               settingsURL: privacyPane("Privacy_Microphone"))
            default:
                return nil
            }
        case .meetingAudio:
            if #unavailable(macOS 14.2) {
                return Problem(message: "Meeting audio needs macOS 14.2 or later. Choose Microphone instead.",
                               settingsURL: nil)
            }
            return nil
        }
    }

    private static func privacyPane(_ anchor: String) -> URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}
