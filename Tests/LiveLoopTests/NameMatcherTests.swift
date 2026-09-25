//
//  NameMatcherTests.swift
//  LiveLoopTests
//
//  Beta — "someone said your name" alert. Matching must be forgiving about
//  case, accents and punctuation, but strict about whole words.
//

import XCTest

final class NameMatcherTests: XCTestCase {

    func testParsesCommaAndNewlineSeparatedTriggers() {
        let matcher = NameMatcher(rawTriggers: " Alex, al \n Hey  Alex ,, ")
        XCTAssertEqual(matcher.triggers, ["alex", "al", "hey alex"])
    }

    func testDropsDuplicatesAfterNormalizing() {
        XCTAssertEqual(NameMatcher(rawTriggers: "Alex, ALEX, alex").triggers, ["alex"])
    }

    func testNormalizationFoldsCaseAccentsAndPunctuation() {
        XCTAssertEqual(NameMatcher.normalize("Chloé, t'es là ?"), "chloe t es la")
        XCTAssertEqual(NameMatcher.normalize("  ANDRÉ—Marie!! "), "andre marie")
    }

    func testMatchesAWholeWordAnywhereInTheTranscript() {
        let matcher = NameMatcher(rawTriggers: "Alex")
        XCTAssertEqual(matcher.firstMatch(in: "Okay so, Alex, what do you think?"), "alex")
        XCTAssertEqual(matcher.firstMatch(in: "alex"), "alex")
    }

    func testDoesNotMatchInsideLongerWords() {
        let matcher = NameMatcher(rawTriggers: "Ann")
        XCTAssertNil(matcher.firstMatch(in: "The annual planning is next week"))
        XCTAssertNil(matcher.firstMatch(in: "Joanna will join later"))
    }

    func testMatchesMultiWordPhrases() {
        let matcher = NameMatcher(rawTriggers: "Mr Garcia")
        XCTAssertEqual(matcher.firstMatch(in: "Thanks, Mr. Garcia!"), "mr garcia")
        XCTAssertNil(matcher.firstMatch(in: "Mr Smith and Garcia"))
    }

    func testMatchesAccentInsensitively() {
        let matcher = NameMatcher(rawTriggers: "Chloé")
        XCTAssertEqual(matcher.firstMatch(in: "chloe can you share your screen"), "chloe")
    }

    func testEmptyTriggersNeverMatch() {
        let matcher = NameMatcher(rawTriggers: " , \n ")
        XCTAssertTrue(matcher.triggers.isEmpty)
        XCTAssertNil(matcher.firstMatch(in: "anything at all"))
    }

    func testIgnoresOverlongTriggers() {
        let long = String(repeating: "x", count: 120)
        XCTAssertEqual(NameMatcher(rawTriggers: "Alex, \(long)").triggers, ["alex"])
    }

    // Partial results from the on-device recognizer revise their last word as
    // more audio arrives, e.g. "The alex" before "The Alexandria office".

    func testTheWordStillBeingSpokenIsNotSettled() {
        let matcher = NameMatcher(rawTriggers: "Alex")
        XCTAssertNil(matcher.firstSettledMatch(in: "The alex", isFinal: false))
        XCTAssertNil(matcher.firstSettledMatch(in: "The Alexandria office", isFinal: false))
    }

    func testAWordFollowedByAnotherIsSettled() {
        let matcher = NameMatcher(rawTriggers: "Alex")
        XCTAssertEqual(matcher.firstSettledMatch(in: "OK thanks everyone alex can", isFinal: false), "alex")
        XCTAssertEqual(matcher.firstSettledMatch(in: "Je crois qu'Alex avait", isFinal: false), "alex")
    }

    func testTheLastWordOfAFinalResultIsSettled() {
        let matcher = NameMatcher(rawTriggers: "Alex")
        XCTAssertEqual(matcher.firstSettledMatch(in: "Thanks, Alex.", isFinal: true), "alex")
    }

    func testAPhraseIsSettledOnlyOnceItsLastWordIs() {
        let matcher = NameMatcher(rawTriggers: "Mr Garcia")
        XCTAssertNil(matcher.firstSettledMatch(in: "Thanks Mr Garcia", isFinal: false))
        XCTAssertEqual(matcher.firstSettledMatch(in: "Thanks Mr Garcia for", isFinal: false), "mr garcia")
    }

    // Names that are also everyday words ("Will", "Pierre", "Chiara"). Given the
    // name as typed, Apple's recognizer writes "Will" for the name and keeps the
    // word "will" in lowercase. A name ending what's been heard counts either way:
    // the listener only acts on it once a pause follows.

    func testKeepsTheTriggersAsTypedForTheRecognizer() {
        XCTAssertEqual(NameMatcher(rawTriggers: " Will, will \n Hey  Alex ").recognizerHints, ["Will", "Hey Alex"])
    }

    func testACommonWordNameIsIgnoredInOrdinarySpeech() {
        let matcher = NameMatcher(rawTriggers: "Will")
        for transcript in [
            "OK let's get started I will send the deck tomorrow will you share your screen",
            "we will see next week that will be all for today",
            "will it be ready by Friday I think it will work",
            "Will you share your screen",
            "OK, let's get started. Will it be ready by Friday?",
        ] {
            XCTAssertNil(matcher.firstSettledMatch(in: transcript, isFinal: true), transcript)
            XCTAssertNil(matcher.firstSettledMatch(in: transcript, isFinal: false), transcript)
        }
        XCTAssertNil(matcher.firstSettledMatch(in: "I will send", isFinal: false))
    }

    func testACommonWordNameCountsWhenUsedAsAName() {
        let matcher = NameMatcher(rawTriggers: "Will")
        XCTAssertEqual(matcher.firstSettledMatch(in: "thanks Will what do you", isFinal: false), "will")
        XCTAssertEqual(matcher.firstSettledMatch(in: "I'll ask Will to send it", isFinal: true), "will")
        XCTAssertEqual(matcher.firstSettledMatch(in: "Will, can you share your screen", isFinal: false), "will")
    }

    func testACommonWordNameEndingWhatWasHeardCountsOnceSettled() {
        // "What do you think, Will?" then silence: `firstMatch` sees it, the
        // listener fires once the recognizer has left it alone for a second.
        let matcher = NameMatcher(rawTriggers: "Will")
        XCTAssertEqual(matcher.firstMatch(in: "what do you think will"), "will")
        XCTAssertNil(matcher.firstSettledMatch(in: "what do you think will", isFinal: false))
        XCTAssertNil(matcher.firstMatch(in: "I will send it"))
    }

    func testCommonWordNamesInOtherLanguages() {
        XCTAssertNil(NameMatcher(rawTriggers: "Pierre").firstMatch(in: "c'est solide comme la pierre et ça tient"))
        XCTAssertEqual(NameMatcher(rawTriggers: "Pierre").firstMatch(in: "merci Pierre on continue"), "pierre")
        XCTAssertNil(NameMatcher(rawTriggers: "Chiara").firstMatch(in: "l'idea è chiara e sarà pronta"))
        XCTAssertNil(NameMatcher(rawTriggers: "Sara").firstMatch(in: "sarà pronta domani mattina"))
    }

    func testSuggestsAFirstNameFromTheAccountName() {
        XCTAssertEqual(NameMatcher.suggestedTrigger(fromFullName: "Alex Garcia"), "Alex")
        XCTAssertEqual(NameMatcher.suggestedTrigger(fromFullName: "  Marie-Claire Dupont "), "Marie-Claire")
        XCTAssertNil(NameMatcher.suggestedTrigger(fromFullName: ""))
        XCTAssertNil(NameMatcher.suggestedTrigger(fromFullName: "   "))
    }

    func testCooldownSuppressesRepeats() {
        var cooldown = AlertCooldown(interval: 20)
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertTrue(cooldown.shouldFire(at: t0))
        XCTAssertFalse(cooldown.shouldFire(at: t0.addingTimeInterval(5)))
        XCTAssertFalse(cooldown.shouldFire(at: t0.addingTimeInterval(19.9)))
        XCTAssertTrue(cooldown.shouldFire(at: t0.addingTimeInterval(20)))
    }
}
