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

    // Real partial results from the on-device recognizer (macOS, en-US):
    // "The Alexandria office…" was briefly guessed as "The alex".

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
