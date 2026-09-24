//
//  NameMatcher.swift
//  LiveLoop
//
//  Beta — "someone said your name". Spots your trigger words in an on-device
//  speech transcript. Forgiving about case, accents and punctuation; strict
//  about whole words, so "Ann" never fires on "annual".
//

import Foundation

struct NameMatcher {

    static let maxTriggerLength = 60

    /// Normalized, de-duplicated triggers in the order they were typed.
    let triggers: [String]

    /// `rawTriggers` is what the user typed: names separated by commas or new lines.
    init(rawTriggers: String) {
        var seen = Set<String>()
        var result: [String] = []
        for piece in rawTriggers.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let trigger = Self.normalize(String(piece))
            guard !trigger.isEmpty, trigger.count <= Self.maxTriggerLength,
                  seen.insert(trigger).inserted else { continue }
            result.append(trigger)
        }
        triggers = result
    }

    /// A sensible first trigger: the first word of the Mac account's full name.
    static func suggestedTrigger(fromFullName fullName: String) -> String? {
        fullName.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    /// Lowercase, accents folded, anything that isn't a letter or digit turned
    /// into a single space.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let spaced = String(folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        })
        return spaced.split(separator: " ").joined(separator: " ")
    }

    /// The first trigger heard as a whole word or phrase, if any.
    func firstMatch(in transcript: String) -> String? {
        guard !triggers.isEmpty else { return nil }
        let padded = " " + Self.normalize(transcript) + " "
        return triggers.first { padded.contains(" \($0) ") }
    }

    /// Like `firstMatch`, but ignoring the word still being spoken: while a
    /// sentence is in progress the recognizer guesses its last word and often
    /// revises it ("The alex…" becomes "The Alexandria office"), so that word
    /// only counts once another word follows it or the result is final.
    func firstSettledMatch(in transcript: String, isFinal: Bool) -> String? {
        guard !isFinal else { return firstMatch(in: transcript) }
        let words = Self.normalize(transcript).split(separator: " ")
        return firstMatch(in: words.dropLast().joined(separator: " "))
    }
}

/// Stops one mention from ringing the alert over and over while the
/// recognizer keeps revising the same sentence.
struct AlertCooldown {

    let interval: TimeInterval
    private var lastFired: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func shouldFire(at now: Date) -> Bool {
        if let lastFired, now.timeIntervalSince(lastFired) < interval { return false }
        lastFired = now
        return true
    }
}
