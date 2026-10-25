import Foundation
import XCTest
@testable import DragonDomain

final class CompanionSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testCountdownIsBoundedAndNeverNegative() {
        let state = CompanionSession(minutes: 25, now: now)
        XCTAssertEqual(state.remainingSeconds(at: now), 1500)
        XCTAssertEqual(state.remainingSeconds(at: now.addingTimeInterval(0.2)), 1500)
        XCTAssertEqual(state.remainingSeconds(at: now.addingTimeInterval(1501)), 0)
        XCTAssertTrue(state.hasExpired(at: state.endsAt))
    }

    func testDurationCannotExceedSessionLimit() {
        XCTAssertEqual(CompanionSession(minutes: -10, now: now).remainingSeconds(at: now), 60)
        XCTAssertEqual(CompanionSession(minutes: Int.max, now: now).remainingSeconds(at: now), 7200)
    }

    func testGreetingsDoNotExtendTheSession() {
        var state = CompanionSession(minutes: 25, now: now)
        let deadline = state.endsAt
        let initialMessage = state.message
        state.greet()
        XCTAssertNotEqual(state.message, initialMessage)
        XCTAssertEqual(state.greetings, 1)
        XCTAssertEqual(state.revision, 1)
        XCTAssertEqual(state.endsAt, deadline)
    }

    func testMoodCyclesAndPreservesTimer() {
        var state = CompanionSession(minutes: 25, now: now)
        let deadline = state.endsAt
        state.cycleMood()
        XCTAssertEqual(state.mood, .cheerful)
        state.cycleMood()
        XCTAssertEqual(state.mood, .sleepy)
        state.cycleMood()
        XCTAssertEqual(state.mood, .calm)
        XCTAssertEqual(state.revision, 3)
        XCTAssertEqual(state.endsAt, deadline)
    }

    func testStateRoundTripsForActivityKit() throws {
        var original = CompanionSession(minutes: 50, now: now)
        original.greet()
        original.cycleMood()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(CompanionSession.self, from: data)
        XCTAssertEqual(restored, original)
    }
}
