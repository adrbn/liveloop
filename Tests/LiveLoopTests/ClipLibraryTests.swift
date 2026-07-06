//
//  ClipLibraryTests.swift
//  LiveLoopTests
//
//  CRUD, ordering, persistence and export for the clip library, exercised
//  against a temporary directory.
//

import XCTest

@MainActor
final class ClipLibraryTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveLoopTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Writes a throwaway file that stands in for a recorded clip.
    private func makeTempFile(_ bytes: String = "video") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mov")
        try? bytes.data(using: .utf8)!.write(to: url)
        return url
    }

    func testAddAndPersist() throws {
        let library = ClipLibrary(directory: tempDir)
        XCTAssertTrue(library.clips.isEmpty)

        let clip = try XCTUnwrap(library.add(movingFileAt: makeTempFile(), name: "First", duration: 5))
        XCTAssertEqual(library.clips.count, 1)
        XCTAssertTrue(library.exists(clip))

        // A fresh instance must load the persisted metadata.
        let reloaded = ClipLibrary(directory: tempDir)
        XCTAssertEqual(reloaded.clips.count, 1)
        XCTAssertEqual(reloaded.clips.first?.name, "First")
    }

    func testPinnedSortFirst() throws {
        let library = ClipLibrary(directory: tempDir)
        let a = try XCTUnwrap(library.add(movingFileAt: makeTempFile(), name: "A", duration: 1))
        let b = try XCTUnwrap(library.add(movingFileAt: makeTempFile(), name: "B", duration: 1))

        library.setPinned(a, true)
        XCTAssertEqual(library.clips.first?.id, a.id, "pinned clip sorts first")
        XCTAssertEqual(library.clips.last?.id, b.id)
    }

    func testRename() throws {
        let library = ClipLibrary(directory: tempDir)
        let clip = try XCTUnwrap(library.add(movingFileAt: makeTempFile(), name: "Old", duration: 1))
        library.rename(clip, to: "New")
        XCTAssertEqual(library.clips.first?.name, "New")
    }

    func testDeleteRemovesFileAndEntry() throws {
        let library = ClipLibrary(directory: tempDir)
        let clip = try XCTUnwrap(library.add(movingFileAt: makeTempFile(), name: "Temp", duration: 1))
        let path = library.url(for: clip).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        library.delete(clip)
        XCTAssertTrue(library.clips.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testExportCopiesFile() throws {
        let library = ClipLibrary(directory: tempDir)
        let clip = try XCTUnwrap(library.add(movingFileAt: makeTempFile("payload"), name: "Exp", duration: 1))
        let destination = tempDir.appendingPathComponent("exported.mov")
        try library.export(clip, to: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "payload")
    }

    func testDropsEntriesWithMissingFiles() throws {
        let library = ClipLibrary(directory: tempDir)
        let clip = try XCTUnwrap(library.add(movingFileAt: makeTempFile(), name: "Ghost", duration: 1))
        // Delete the underlying file behind the library's back.
        try FileManager.default.removeItem(at: library.url(for: clip))

        let reloaded = ClipLibrary(directory: tempDir)
        XCTAssertTrue(reloaded.clips.isEmpty, "entries without files are pruned on load")
    }
}
