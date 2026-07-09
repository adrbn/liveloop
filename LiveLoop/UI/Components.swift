//
//  Components.swift
//  LiveLoop
//
//  Small reusable UI pieces for the menu-bar panel: clip thumbnails and
//  keyboard-shortcut badges.
//

import SwiftUI
import AVFoundation

extension Color {
    /// LiveLoop's brand tint — the indigo midpoint of the blue→violet icon.
    static let brand = Color(red: 0.42, green: 0.44, blue: 0.96)
}

enum Links {
    static let github = URL(string: "https://github.com/adrbn/liveloop")!
    static let kofi = URL(string: "https://ko-fi.com/adrbn")!
}

/// Resolves the NSWindow hosting a SwiftUI view — used to scope key shortcuts to
/// the menu-bar panel. Reports the window whenever it changes (including nil).
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

/// Async, cached first-frame thumbnails for clips (keyed by url + size).
actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [String: NSImage] = [:]

    func thumbnail(for url: URL, maxWidth: CGFloat = 160) async -> NSImage? {
        let key = "\(url.path)|\(Int(maxWidth))"
        if let cached = cache[key] { return cached }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 0.75)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache[key] = image
        return image
    }
}

struct ClipThumbnailView: View {
    let url: URL
    var size = CGSize(width: 46, height: 30)
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) { image = await ThumbnailCache.shared.thumbnail(for: url) }
    }
}

/// A larger first-frame backdrop of a clip (for the idle preview area).
struct ClipBackdropView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.10)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: url) { image = await ThumbnailCache.shared.thumbnail(for: url, maxWidth: 700) }
    }
}

/// An AppKit-backed inline text field that reliably commits on Return (and on
/// focus loss) inside a menu-bar popover, where SwiftUI's `.onSubmit` is flaky.
struct RenameField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit(_:))
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: RenameField
        private var committed = false
        init(_ parent: RenameField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }

        @objc func commit(_ sender: NSTextField) {
            guard !committed else { return }
            committed = true
            parent.text = sender.stringValue
            parent.onCommit()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { commit(field) }
        }
    }
}

/// Renders a shortcut like "⌥⌘L" as small key-cap badges.
struct HotkeyBadge: View {
    let display: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(display.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(.system(size: 11, weight: .semibold))
                    .frame(minWidth: 17, minHeight: 17)
                    .background(Color.primary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.10)))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
