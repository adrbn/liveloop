//
//  ExtensionManager.swift
//  LiveLoop
//
//  Drives installation / removal of the camera system extension through
//  OSSystemExtensionManager and surfaces progress to the UI.
//

import Foundation
import SystemExtensions
import os.log

private let logger = Logger(subsystem: "com.adrbn.LiveLoop", category: "ExtensionManager")

@MainActor
final class ExtensionManager: NSObject, ObservableObject {

    enum Status: Equatable {
        case unknown
        case installing
        case needsApproval
        case installed
        case removed
        case failed(String)

        var isBusy: Bool { self == .installing }
    }

    @Published private(set) var status: Status = .unknown
    private var isRemoving = false

    /// Request activation of the LiveLoop camera extension. macOS shows a
    /// System Settings approval prompt the first time.
    func install() {
        logger.info("Requesting activation of \(LiveLoop.extensionBundleID, privacy: .public)")
        isRemoving = false
        status = .installing
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: LiveLoop.extensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Request removal of the extension.
    func uninstall() {
        logger.info("Requesting deactivation of \(LiveLoop.extensionBundleID, privacy: .public)")
        isRemoving = true
        status = .installing
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: LiveLoop.extensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

extension ExtensionManager: OSSystemExtensionRequestDelegate {

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Always upgrade to the version bundled with this app.
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            self.status = .needsApproval
            logger.info("Extension needs user approval in System Settings.")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            switch result {
            case .completed:
                self.status = self.isRemoving ? .removed : .installed
                logger.info("Extension request completed (removing: \(self.isRemoving, privacy: .public)).")
            case .willCompleteAfterReboot:
                self.status = .needsApproval
                logger.info("Extension will complete after reboot.")
            @unknown default:
                self.status = self.isRemoving ? .removed : .installed
            }
            self.isRemoving = false
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRemoving = false
            self.status = .failed(error.localizedDescription)
            logger.error("Extension request failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
