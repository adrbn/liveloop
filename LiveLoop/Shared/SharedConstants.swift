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

    /// App Group used for the app's `UserDefaults` suite. The extension runs as
    /// another user and can't read it. Both targets declare this in their
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
        /// User-customised virtual-camera display name (app side; the extension
        /// gets it through `CameraName`).
        static let cameraName = "cameraName"
    }

    /// Cross-process Darwin notifications the extension posts when a meeting app
    /// starts or stops consuming the virtual camera. The app listens so it can
    /// turn the real webcam on *only* while something is actually watching
    /// (engage-on-demand) instead of forcing a manual "Start camera".
    enum ConsumerSignal {
        static let active = "com.adrbn.LiveLoop.consumerActive"
        static let inactive = "com.adrbn.LiveLoop.consumerInactive"

        /// Posted by the extension on the 0↔︎1 consumer transition.
        static func post(active isActive: Bool) {
            let name = CFNotificationName(rawValue: (isActive ? active : inactive) as CFString)
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
        }
    }

    /// The picture the camera shows while the app isn't sending video, sent by
    /// the app as a custom device property: the JPEG as a base64 string (CMIO
    /// silently drops data values on custom properties; strings get through). The extension runs as a different
    /// user, so it can't read the app's files or App Group defaults; it keeps
    /// its own copy instead.
    enum OffAirPicture {
        /// FourCC `'plch'`, the selector the app sets.
        static let selector: UInt32 = 0x70_6C_63_68
        /// The same property as the extension declares it.
        static let propertyName = "4cc_plch_glob_0000"
        /// JPEG data larger than this is ignored. An empty string restores the default card.
        static let maxBytes = 4_000_000
    }

    /// The display name the app sends as a custom device property (a string).
    /// The extension keeps its own copy and republishes the camera under it
    /// (a published CMIO device's name is fixed).
    enum CameraName {
        /// FourCC `'llcn'`, the selector the app sets. Not `'lnam'`: that's
        /// CMIO's own read-only object name.
        static let selector: UInt32 = 0x6C_6C_63_6E
        /// The same property as the extension declares it.
        static let propertyName = "4cc_llcn_glob_0000"
    }

    /// The shared defaults suite, or `.standard` if the App Group is unavailable
    /// (e.g. entitlement not provisioned) so the app still runs.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// The display name to publish for a user's override (blank = the default).
    static func cameraName(from name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultCameraName : trimmed
    }
}
