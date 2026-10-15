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
    /// Part of the playlist: selecting it loops every playlist clip in turn.
    var inPlaylist: Bool

    init(id: UUID = UUID(),
         name: String,
         fileName: String,
         durationSeconds: Double,
         createdAt: Date = Date(),
         pinned: Bool = false,
         inPlaylist: Bool = false) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.pinned = pinned
        self.inPlaylist = inPlaylist
    }

    /// Libraries saved before playlists existed have no `inPlaylist` key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fileName = try c.decode(String.self, forKey: .fileName)
        durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        inPlaylist = try c.decodeIfPresent(Bool.self, forKey: .inPlaylist) ?? false
    }
}
