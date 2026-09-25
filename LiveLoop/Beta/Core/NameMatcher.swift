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

    /// Names that are also everyday words in English, French or Italian ("I will",
    /// "la pierre", "sarà"). Heard in lowercase they're the word, not the name.
    static let commonWordNames: Set<String> = Set((
        "will bill mark grace hope rose pat sue may june april frank rich rob guy jack joy faith art chase dawn drew gene max " +
        "nick ray sandy summer amber carol chip crystal daisy glen holly iris ivy jade lily lance miles norm penny pearl reed " +
        "ruby rusty sky sunny wade woody autumn brook cliff dean don hunter mason pepper basil cash heather hazel olive violet " +
        "sage roger jean ben al " +
        "pierre claire prudence constance aime aimee blanche celeste desire desiree juste modeste pascal clement aurore colombe " +
        "victoire marine melodie violette perle capucine ambre cerise prune fleur lys parfait fortune noel olivier marin " +
        "constant innocent honore ange " +
        "serena felice rosa gioia fortunato giusto leone vera marina stella aurora speranza innocente benedetto onesto " +
        "viola chiara angelo sole luce sereno franco grazia fiore primo santo massimo vittoria letizia libero fausto " +
        "salvatore alba sara gemma perla ambra fede mia bruno moreno candido lupo"
    ).split(separator: " ").map(String.init))

    /// Normalized, de-duplicated triggers in the order they were typed.
    let triggers: [String]

    /// The same triggers as typed, for the recognizer: given "Will", it writes
    /// the name "Will" and keeps the word "will" in lowercase.
    let recognizerHints: [String]

    /// `rawTriggers` is what the user typed: names separated by commas or new lines.
    init(rawTriggers: String) {
        var seen = Set<String>()
        var result: [String] = []
        var hints: [String] = []
        for piece in rawTriggers.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let trigger = Self.normalize(String(piece))
            guard !trigger.isEmpty, trigger.count <= Self.maxTriggerLength,
                  seen.insert(trigger).inserted else { continue }
            result.append(trigger)
            hints.append(piece.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        }
        triggers = result
        recognizerHints = hints
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
        firstMatch(among: Self.words(in: transcript))
    }

    /// Like `firstMatch`, but ignoring the word still being spoken: while a
    /// sentence is in progress the recognizer guesses its last word and often
    /// revises it ("The alex…" becomes "The Alexandria office"), so that word
    /// only counts once another word follows it or the result is final.
    func firstSettledMatch(in transcript: String, isFinal: Bool) -> String? {
        let words = Self.words(in: transcript)
        return firstMatch(among: isFinal ? words : Array(words.dropLast()))
    }

    private func firstMatch(among words: [Word]) -> String? {
        guard !triggers.isEmpty else { return nil }
        let padded = " " + words.map(\.key).joined(separator: " ") + " "
        return triggers.first { trigger in
            guard Self.commonWordNames.contains(trigger) else { return padded.contains(" \(trigger) ") }
            return words.contains { $0.key == trigger && $0.soundsLikeAName }
        }
    }

    /// One word of a transcript, as the recognizer wrote it.
    private struct Word {
        let key: String
        let isCapitalized: Bool
        /// First word, or right after . ! ? …
        let opensSentence: Bool
        /// Followed by , ! ? . … : ;
        let isCalledOut: Bool
        /// Nothing heard after it (yet).
        let isLast: Bool

        /// For a name that's also a word: the name is capitalized, except that
        /// opening a sentence only counts when called out ("Will, can you…").
        /// Ending what's been heard counts either way — the listener only acts
        /// on that once a pause follows ("What do you think, will…").
        var soundsLikeAName: Bool {
            isLast || (isCapitalized && (!opensSentence || isCalledOut))
        }
    }

    private static let sentenceEnds = CharacterSet(charactersIn: ".!?…")
    private static let callOuts = CharacterSet(charactersIn: ",!?.…:;")

    private static func words(in transcript: String) -> [Word] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in transcript.indices {
            let inWord = transcript[index].unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            if inWord, start == nil { start = index }
            if !inWord, let wordStart = start {
                ranges.append(wordStart..<index)
                start = nil
            }
        }
        if let wordStart = start { ranges.append(wordStart..<transcript.endIndex) }

        return ranges.enumerated().map { n, range in
            let before = transcript[(n == 0 ? transcript.startIndex : ranges[n - 1].upperBound)..<range.lowerBound]
            let after = transcript[range.upperBound..<(n + 1 < ranges.count ? ranges[n + 1].lowerBound : transcript.endIndex)]
            return Word(key: normalize(String(transcript[range])),
                        isCapitalized: transcript[range].first?.isUppercase == true,
                        opensSentence: n == 0 || before.unicodeScalars.contains { sentenceEnds.contains($0) },
                        isCalledOut: after.unicodeScalars.contains { callOuts.contains($0) },
                        isLast: n == ranges.count - 1)
        }
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
