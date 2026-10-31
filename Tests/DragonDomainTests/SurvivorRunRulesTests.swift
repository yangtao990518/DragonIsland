import Foundation
import XCTest
@testable import DragonDomain

final class SurvivorRunRulesTests: XCTestCase {
    func testStandardRunIsTwentyMinutesWithContinuousStages() throws {
        let config = SurvivorRunConfiguration.standard
        XCTAssertEqual(config.duration, 1200)
        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.stages.map(\.startsAt), [0, 180, 480, 840, 1080])
        XCTAssertEqual(config.stages.last?.endsAt, 1200)
    }

    func testStageBoundaryHasExactlyOneStageAndStopsAtTwentyMinutes() {
        let config = SurvivorRunConfiguration.standard
        XCTAssertEqual(config.stage(at: 179.99)?.id, "opening")
        XCTAssertEqual(config.stage(at: 180)?.id, "growth")
        XCTAssertEqual(config.stage(at: 1199.99)?.id, "finale")
        for time in [-1.0, 1200, .infinity, .nan] { XCTAssertNil(config.stage(at: time)) }
    }

    func testInvalidGapOverlapAndDuplicateStagesAreRejected() {
        for start in [9.0, 11] {
            let config = SurvivorRunConfiguration(duration: 20, stages: [
                .init(id: "one", startsAt: 0, endsAt: 10, spawnInterval: 1, enemyLimit: 10),
                .init(id: "two", startsAt: start, endsAt: 20, spawnInterval: 1, enemyLimit: 10)
            ])
            XCTAssertThrowsError(try config.validate())
        }
        let duplicate = SurvivorRunConfiguration(duration: 20, stages: [
            .init(id: "same", startsAt: 0, endsAt: 10, spawnInterval: 1, enemyLimit: 10),
            .init(id: "same", startsAt: 10, endsAt: 20, spawnInterval: 1, enemyLimit: 10)
        ])
        XCTAssertThrowsError(try duplicate.validate())
    }

    func testSeventyTwoThousandSixtyHzTicksEndAtExactlyTwentyMinutes() throws {
        var clock = try SurvivorRunClock()
        try clock.advance(by: 10)
        XCTAssertEqual(clock.elapsed, 0)
        clock.start()
        for _ in 0..<72_000 { try clock.advance(by: 1.0 / 60) }
        XCTAssertEqual(clock.elapsed, 1200)
        XCTAssertTrue(clock.finished)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(clock.remaining, 0)
    }

    func testUpgradeMenuAndBackgroundPauseMustBeResumedIndependently() throws {
        var clock = try SurvivorRunClock()
        clock.start(); try clock.advance(by: 180)
        clock.pause(.upgrade); clock.pause(.menu); clock.pause(.background)
        try clock.advance(by: 900)
        XCTAssertEqual(clock.elapsed, 180)
        clock.resume(.background); clock.resume(.menu)
        XCTAssertFalse(clock.running, "Returning to the app must not unpause an upgrade selection")
        try clock.advance(by: 600)
        XCTAssertEqual(clock.elapsed, 180)
        clock.resume(.upgrade); try clock.advance(by: 1)
        XCTAssertEqual(clock.elapsed, 181)
        XCTAssertTrue(clock.running)
    }

    func testInvalidDeltaNeverChangesClockAndOvershootIsClamped() throws {
        var clock = try SurvivorRunClock(); clock.start()
        for delta in [-1.0, .nan, .infinity] {
            XCTAssertThrowsError(try clock.advance(by: delta))
            XCTAssertEqual(clock.elapsed, 0)
        }
        try clock.advance(by: 2000)
        XCTAssertEqual(clock.elapsed, 1200)
        try clock.advance(by: 100)
        XCTAssertEqual(clock.elapsed, 1200)
    }

    func testSavedClockRetainsActiveTimeAndPauseStateWithoutCountingOfflineTime() throws {
        var clock = try SurvivorRunClock(); clock.start()
        try clock.advance(by: 450); clock.pause(.background)
        var restored = try JSONDecoder().decode(SurvivorRunClock.self, from: JSONEncoder().encode(clock))
        XCTAssertEqual(restored, clock)
        try restored.advance(by: 10_000)
        XCTAssertEqual(restored.elapsed, 450)
        restored.resume(.background); try restored.advance(by: 1)
        XCTAssertEqual(restored.elapsed, 451)
    }

    func testInvalidSavedClockCannotRestoreAnImpossibleRun() throws {
        let cases: [[String: Any]] = [
            ["duration":1200,"elapsed":1201,"started":true,"pauseReasons":[]],
            ["duration":1200,"elapsed":10,"started":false,"pauseReasons":[]],
            ["duration":0,"elapsed":0,"started":false,"pauseReasons":[]]
        ]
        for values in cases {
            let data = try JSONSerialization.data(withJSONObject: values)
            XCTAssertThrowsError(try JSONDecoder().decode(SurvivorRunClock.self, from: data))
        }
    }
}
