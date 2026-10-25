import Foundation
import XCTest
@testable import DragonDomain

final class CompanionMotionTests: XCTestCase {
    func testMotionPreservesDeadlineAndIndependentCounters() {
        var session = CompanionSession(minutes: 25)
        let deadline = session.endsAt
        session.performMotion(.roll)
        session.performMotion(.walk)
        session.performMotion(.roll)
        XCTAssertEqual(session.rollTurns, 2)
        XCTAssertEqual(session.walkSteps, 1)
        XCTAssertEqual(session.motionSequence, 3)
        XCTAssertEqual(session.endsAt, deadline)
    }

    func testPreMotionSessionStillDecodes() throws {
        let data = try JSONEncoder().encode(CompanionSession(minutes: 1))
        let legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let decoded = try JSONDecoder().decode(CompanionSession.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.motion)
        XCTAssertNil(decoded.motionSequence)
        var updated = decoded
        updated.performMotion(.walk)
        XCTAssertEqual(updated.walkSteps, 1)
    }
}
