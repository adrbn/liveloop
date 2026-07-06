//
//  main.swift
//  LiveLoopExtension
//
//  Entry point for the CMIO camera system extension. macOS launches this
//  executable when the extension is activated; it registers the virtual-camera
//  provider and then runs the run loop forever.
//

import Foundation
import CoreMediaIO

let providerSource = ExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
