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

    func testLegacyTimelineStillDecodesWithoutPreviewOrLegMetadata() throws {
        let data = Data(#"{"fps":30,"period":60,"plans":[{"id":0,"mask":0,"slots":["idle"],"frames":[{"asset":"idle","x":0,"action":"idle"}]}]}"#.utf8)
        let timeline = try JSONDecoder().decode(MotionTimeline.self, from: data)
        XCTAssertNil(timeline.previews)
        XCTAssertNil(timeline.plans.first?.legs)
        XCTAssertEqual(timeline.frame(plan: 0, elapsed: 100)?.asset, "idle")
    }

    func testPreviewRetainsTravelAndLoopsWithoutJumpingToAnotherAction() throws {
        let data = Data(#"{"fps":1,"period":60,"plans":[],"previews":{"roll":[{"asset":"roll_right","x":-50,"action":"roll"},{"asset":"roll_left","x":50,"action":"roll"}]}}"#.utf8)
        let timeline = try JSONDecoder().decode(MotionTimeline.self, from: data)
        XCTAssertEqual(timeline.preview(action: "roll", elapsed: 0)?.x, -50)
        XCTAssertEqual(timeline.preview(action: "roll", elapsed: 1)?.asset, "roll_left")
        XCTAssertEqual(timeline.preview(action: "roll", elapsed: 2)?.x, -50)
        XCTAssertNil(timeline.preview(action: "walk_right", elapsed: 0))
    }
}

