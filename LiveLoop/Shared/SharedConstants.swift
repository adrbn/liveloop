//
//  SharedConstants.swift
//  Shared between the LiveLoop app and the LiveLoopExtension camera extension.
//
//  Keep this file dependency-free (Foundation only) so it can compile into the
//  sandboxed system extension as well as the main app.
//

import Foundation
import CoreVideo

/// Identifiers and defaults shared across the app and its camera extension.
///
/// The app and the extension are separate processes that never share memory, so
/// every value they must agree on lives here as a single source of truth.
enum LiveLoop {

    /// Bundle identifier of the camera system extension. Must match the value in
    /// `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`) exactly — it is what
    /// `OSSystemExtensionManager` activates.
    static let extensionBundleID = "com.adrbn.LiveLoop.Extension"

    /// App Group used for the shared `UserDefaults` suite (settings such as the
    /// virtual-camera display name). Both targets declare this in their
    /// entitlements. Team-prefixed so it also prefixes the extension's CMIO Mach
    /// service name (a CMIO requirement).
    static let appGroupID = "2TWQF4T93E.com.adrbn.LiveLoop"

    /// Default display name of the virtual camera as seen by Zoom, Meet, etc.
    static let defaultCameraName = "LiveLoop"

    /// Stable identifiers so the extension always publishes the same device and
    /// the app can find it by UID regardless of the (customisable) display name.
    static let deviceUID = "5C0B4E2A-1F3D-4A6B-9C7E-1D2E3F4A5B6C"
    static let sourceStreamUID = "6D1C5F3B-2A4E-4B7C-8D9F-2E3F4A5B6C7D"
    static let sinkStreamUID = "7E2D6A4C-3B5F-4C8D-9EAF-3F4A5B6C7D8E"

    /// Fixed output geometry of the virtual camera. A single, well-supported
    /// format keeps the extension simple and every conferencing app happy.
    static let frameWidth: Int32 = 1920
    static let frameHeight: Int32 = 1080
    static let frameRate: Int32 = 30

    /// Pixel format the extension advertises and the app must feed. BGRA is the
    /// most broadly compatible zero-conversion format for CMIO clients.
    static let pixelFormat = kCVPixelFormatType_32BGRA

    /// Keys for the shared `UserDefaults` suite.
    enum DefaultsKey {
        /// User-customised virtual-camera display name (a free "Pro" feature).
        static let cameraName = "cameraName"
    }

    /// The shared defaults suite, or `.standard` if the App Group is unavailable
    /// (e.g. entitlement not provisioned) so the app still runs.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Current virtual-camera display name, honouring the user's override.
    static var cameraName: String {
        let name = sharedDefaults.string(forKey: DefaultsKey.cameraName)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultCameraName : trimmed
    }
}
