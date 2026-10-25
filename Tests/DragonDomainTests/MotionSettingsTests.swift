import Foundation
import XCTest
@testable import DragonDomain

final class MotionSettingsTests: XCTestCase {
    func testCheckedActionsSelectOnlyTheirBankAndOffIsStatic() {
        for mask in 0..<4 {
            let settings = MotionSettings(automatic: true, walk: mask & 1 != 0, roll: mask & 2 != 0)
            XCTAssertEqual(settings.mask, mask)
            for seed in 0..<20 { XCTAssertEqual(settings.plan(seed: seed)! / 2, mask) }
        }
        XCTAssertNil(MotionSettings(automatic: false, walk: true, roll: true).plan(seed: 0))
    }
    func testLegacySessionDecodesWithoutAutomaticMotion() throws {
        let old = Data("{\"startedAt\":0,\"endsAt\":60,\"mood\":\"calm\",\"message\":\"hello\",\"greetings\":0,\"revision\":0}".utf8)
        let state = try JSONDecoder().decode(CompanionSession.self, from: old)
        XCTAssertNil(state.automaticMotionPlan)
        XCTAssertNil(state.motionEpoch)
        XCTAssertEqual(state.islandScene, .black)
    }

    func testSceneStateRoundTripsWithoutChangingTimerOrMotion() throws {
        var state = CompanionSession(minutes: 25, now: Date(timeIntervalSince1970: 1000))
        state.automaticMotionPlan = 6
        state.motionEpoch = state.startedAt
        let original = state
        state.islandSceneID = IslandScene.meadow.rawValue
        let restored = try JSONDecoder().decode(CompanionSession.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.islandScene, .meadow)
        XCTAssertEqual(restored.startedAt, original.startedAt)
        XCTAssertEqual(restored.endsAt, original.endsAt)
        XCTAssertEqual(restored.motionEpoch, original.motionEpoch)
        XCTAssertEqual(restored.automaticMotionPlan, original.automaticMotionPlan)
    }

    func testUnknownSceneFallsBackToClassicBlack() {
        XCTAssertEqual(IslandScene.resolve(nil), .black)
        XCTAssertEqual(IslandScene.resolve("future-scene"), .black)
        XCTAssertEqual(IslandScene.resolve("night"), .night)
    }
}
