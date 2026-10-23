import XCTest

final class KeepActivePolicyTests: XCTestCase {

    func testNudgesOnlyWhenLoopingAndIdle() {
        let idle = KeepActivePolicy.idleThreshold
        XCTAssertTrue(KeepActivePolicy.shouldNudge(isLooping: true, idleSeconds: idle))
        XCTAssertFalse(KeepActivePolicy.shouldNudge(isLooping: true, idleSeconds: idle - 1))
        XCTAssertFalse(KeepActivePolicy.shouldNudge(isLooping: false, idleSeconds: idle * 10))
    }
}
