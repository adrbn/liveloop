//
//  ClipLibrary.swift
//  LiveLoop
//
//  The saved-clip store: metadata in `metadata.json` and video files alongside
//  it, in the App Group container so the (sandboxed) extension could read them
//  too if ever needed. All the "Pro" limits are gone — unlimited clips, any
//  length, import/export, and pinning are standard here.
//
//  The base directory is injectable so the CRUD logic can be unit-tested against
//  a temporary folder.
//

import Foundation
import AVFoundation

@MainActor
final class ClipLibrary: ObservableObject {

    @Published private(set) var clips: [Clip] = []

    let directory: URL
    private var metadataURL: URL { directory.appendingPathComponent("metadata.json") }
    /// Where `delete` parks a clip's file so an in-session undo can bring it back.
    private var trashDirectory: URL { directory.appendingPathComponent(".trash", isDirectory: true) }

    init(directory: URL = ClipLibrary.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        // Clips deleted in a previous session can't be undone anymore — discard them.
        try? FileManager.default.removeItem(at: trashDirectory)
    }

    // MARK: - Locations

    nonisolated static func defaultDirectory() -> URL {
        let fm = FileManager.default
        let base: URL
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: LiveLoop.appGroupID) {
            base = group
        } else {
            base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LiveLoop", isDirectory: true)
        }
        return base.appendingPathComponent("Clips", isDirectory: true)
    }

    func url(for clip: Clip) -> URL {
        directory.appendingPathComponent(clip.fileName)
    }

    // MARK: - Create

    /// Moves a freshly recorded temp file into the library.
    @discardableResult
    func add(movingFileAt tempURL: URL, name: String, duration: Double) -> Clip? {
        let fileName = "\(UUID().uuidString).mov"
        let destination = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            return nil
        }
        let clip = Clip(name: name, fileName: fileName, durationSeconds: duration)
        clips = sorted(clips + [clip])
        persist()
        return clip
    }

    /// Copies an external video into the library (import feature).
    @discardableResult
    func importClip(from sourceURL: URL, name: String? = nil) async -> Clip? {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            return nil
        }
        let duration = await Self.duration(of: destination)
        let clip = Clip(name: name ?? sourceURL.deletingPathExtension().lastPathComponent,
                        fileName: fileName,
                        durationSeconds: duration)
        clips = sorted(clips + [clip])
        persist()
        return clip
    }

    // MARK: - Read

    func exists(_ clip: Clip) -> Bool {
        FileManager.default.fileExists(atPath: url(for: clip).path)
    }

    // MARK: - Update

    func rename(_ clip: Clip, to newName: String) {
        update(clip) { $0.name = newName.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func setPinned(_ clip: Clip, _ pinned: Bool) {
        update(clip) { $0.pinned = pinned }
    }

    /// Copies a clip's video out to a user-chosen destination (export feature).
    func export(_ clip: Clip, to destination: URL) throws {
        let source = url(for: clip)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    // MARK: - Delete

    /// Removes a clip from the library, parking its file in the trash so the
    /// deletion can be undone within the session (see `restore`).
    func delete(_ clip: Clip) {
        let source = url(for: clip)
        if FileManager.default.fileExists(atPath: source.path) {
            try? FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            let parked = trashDirectory.appendingPathComponent(clip.fileName)
            try? FileManager.default.removeItem(at: parked)   // clear any stale copy
            try? FileManager.default.moveItem(at: source, to: parked)
        }
        clips = clips.filter { $0.id != clip.id }
        persist()
    }

    /// Brings a just-deleted clip back (undo): moves its file out of the trash
    /// and re-inserts it. Returns false if the file is no longer recoverable.
    @discardableResult
    func restore(_ clip: Clip) -> Bool {
        guard !clips.contains(where: { $0.id == clip.id }) else { return true }
        let destination = url(for: clip)
        let parked = trashDirectory.appendingPathComponent(clip.fileName)
        if !FileManager.default.fileExists(atPath: destination.path),
           FileManager.default.fileExists(atPath: parked.path) {
            try? FileManager.default.moveItem(at: parked, to: destination)
        }
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        clips = sorted(clips + [clip])
        persist()
        return true
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([Clip].self, from: data) else {
            clips = []
            return
        }
        // Drop entries whose files vanished (e.g. manual deletion).
        clips = sorted(decoded.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path)
        })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(clips) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Helpers

    private func update(_ clip: Clip, _ mutate: (inout Clip) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        var copy = clips[index]
        mutate(&copy)
        var newClips = clips
        newClips[index] = copy
        clips = sorted(newClips)
        persist()
    }

    /// Pinned clips first, newest first within each group.
    private func sorted(_ input: [Clip]) -> [Clip] {
        input.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }
}
