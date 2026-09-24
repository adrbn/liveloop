//
//  AutomationCommandTests.swift
//  LiveLoopTests
//
//  Beta — the liveloop:// URL scheme used by Shortcuts, Stream Deck, Raycast,
//  Alfred and AppleScript (`open location`).
//

import XCTest

final class AutomationCommandTests: XCTestCase {

    private func command(_ string: String) -> AutomationCommand? {
        URL(string: string).flatMap(AutomationCommand.init(url:))
    }

    func testBasicCommands() {
        XCTAssertEqual(command("liveloop://toggle"), .toggle)
        XCTAssertEqual(command("liveloop://loop"), .loop)
        XCTAssertEqual(command("liveloop://live"), .live)
        XCTAssertEqual(command("liveloop://start"), .startCamera)
        XCTAssertEqual(command("liveloop://stop"), .stopCamera)
    }

    func testAliases() {
        XCTAssertEqual(command("liveloop://away"), .loop)
        XCTAssertEqual(command("liveloop://back"), .live)
        XCTAssertEqual(command("liveloop://on"), .startCamera)
        XCTAssertEqual(command("liveloop://off"), .stopCamera)
    }

    func testIsCaseInsensitiveAndIgnoresTrailingSlash() {
        XCTAssertEqual(command("LIVELOOP://Toggle"), .toggle)
        XCTAssertEqual(command("liveloop://loop/"), .loop)
    }

    func testOpaqueFormWithoutSlashes() {
        XCTAssertEqual(command("liveloop:toggle"), .toggle)
    }

    func testClipByQueryName() {
        XCTAssertEqual(command("liveloop://clip?name=Coffee%20break"), .selectClip("Coffee break"))
    }

    func testClipByPath() {
        XCTAssertEqual(command("liveloop://clip/Coffee%20break"), .selectClip("Coffee break"))
    }

    func testClipWithoutNameIsRejected() {
        XCTAssertNil(command("liveloop://clip"))
        XCTAssertNil(command("liveloop://clip?name=%20%20"))
    }

    func testRejectsOtherSchemesAndUnknownCommands() {
        XCTAssertNil(command("https://toggle"))
        XCTAssertNil(command("liveloop://format-disk"))
        XCTAssertNil(command("liveloop://"))
    }

    func testRejectsOverlongClipNames() {
        let long = String(repeating: "a", count: 300)
        XCTAssertNil(command("liveloop://clip?name=\(long)"))
    }
    // Settings ▸ Beta offers these links to copy, so each must parse back.

    func testEveryCommandHasALinkThatParsesBackToItself() {
        let commands: [AutomationCommand] = [
            .toggle, .loop, .live, .startCamera, .stopCamera,
            .selectClip("Coffee break"), .selectClip("Café & croissant"), .selectClip("50% = 2/4?"),
        ]
        for command in commands {
            XCTAssertEqual(AutomationCommand(url: command.url), command, command.url.absoluteString)
        }
    }

    // A clip link finds its clip by name, so Settings offers one link per
    // name, compared the way the link is resolved.

    func testClipNamesMatchIgnoringCaseAccentsAndSurroundingSpaces() {
        XCTAssertTrue(AutomationCommand.clipNamesMatch("Café break", " cafe BREAK "))
        XCTAssertFalse(AutomationCommand.clipNamesMatch("Clip 6", "Clip 7"))
    }

    func testLinkableClipNamesListEachNameOnceInOrder() {
        let names = ["Clip 6", "Coffee break", "clip 6", "Café", "Cafe", "  Stand-up ", "   "]
        XCTAssertEqual(AutomationCommand.linkableClipNames(names), ["Clip 6", "Coffee break", "Café", "Stand-up"])
    }

    func testLinksAreReadable() {
        XCTAssertEqual(AutomationCommand.toggle.url.absoluteString, "liveloop://toggle")
        XCTAssertEqual(AutomationCommand.startCamera.url.absoluteString, "liveloop://start")
        XCTAssertEqual(AutomationCommand.selectClip("Coffee break").url.absoluteString,
                       "liveloop://clip?name=Coffee%20break")
    }
}
