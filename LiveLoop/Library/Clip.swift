//
//  Clip.swift
//  LiveLoop
//
//  Metadata for a single saved loop clip. The video itself lives beside the
//  library's `metadata.json` in the clips directory.
//

import Foundation

struct Clip: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// File name (not full path) inside the clips directory.
    let fileName: String
    var durationSeconds: Double
    let createdAt: Date
    var pinned: Bool

    init(id: UUID = UUID(),
         name: String,
         fileName: String,
         durationSeconds: Double,
         createdAt: Date = Date(),
         pinned: Bool = false) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.pinned = pinned
    }
}
