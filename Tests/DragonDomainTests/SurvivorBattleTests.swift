import Foundation
import XCTest
@testable import DragonDomain

final class SurvivorBattleTests: XCTestCase {
    func testMovementNormalizesDiagonalAndKeepsFacingForVerticalMotion() throws {
        var game = try SurvivorBattle()
        try game.advance(by: 0.1, movement: .init(x: 1, y: 1))
        XCTAssertEqual(game.player.length, game.playerSpeed * 0.1, accuracy: 0.001)
        XCTAssertFalse(game.facingLeft)
        try game.advance(by: 0.1, movement: .init(x: 0, y: -1))
        XCTAssertFalse(game.facingLeft)
        try game.advance(by: 0.1, movement: .init(x: -1, y: 0))
        XCTAssertTrue(game.facingLeft)
    }

    func testIndependentPausesFreezeCombatAndDoNotCancelUpgrade() throws {
        var game = try SurvivorBattle()
        game.awardExperience(game.experienceNeeded)
        game.pause(.menu); game.pause(.background)
        game.takeDamage(50)
        try game.advance(by: 100, movement: .init(x: 1, y: 0))
        XCTAssertEqual(game.health, 100)
        XCTAssertEqual(game.player, .zero)
        XCTAssertEqual(game.clock.elapsed, 0)
        game.resume(.background); game.resume(.menu)
        XCTAssertFalse(game.clock.running)
        XCTAssertTrue(game.choose(.thunder))
        XCTAssertTrue(game.clock.running)
    }

    func testBubbleAttacksKillAndAwardExperienceWithoutAttackInput() throws {
        var game = try SurvivorBattle()
        game.spawnEnemy(at: .init(x: 65, y: 0), kind: .demon)
        try game.advance(by: 1.5, movement: .zero)
        XCTAssertGreaterThanOrEqual(game.kills, 1)
        XCTAssertGreaterThan(game.experience + game.drops.reduce(0) { $0 + $1.value }, 0)
        let kills = game.kills
        try game.advance(by: 0.1, movement: .zero)
        XCTAssertEqual(game.kills, kills)
    }

    func testSweptCollisionFindsTargetBetweenProjectileEndpoints() {
        XCTAssertEqual(SurvivorBattle.segmentDistance(.init(x: 50, y: 3), .zero, .init(x: 100, y: 0)), 3, accuracy: 0.001)
        XCTAssertEqual(SurvivorBattle.segmentDistance(.init(x: -5, y: 0), .zero, .init(x: 100, y: 0)), 5)
    }

    func testLearningThunderAutocastsFullSourceDuration() throws {
        var game = try SurvivorBattle(thunderDuration: 4.096009)
        game.awardExperience(game.experienceNeeded)
        XCTAssertTrue(game.choices.contains(.thunder))
        XCTAssertFalse(game.choose(.mend))
        XCTAssertTrue(game.choose(.thunder))
        game.spawnEnemy(at: .init(x: 200, y: 0), kind: .boss)
        try game.advance(by: 0.2, movement: .zero)
        XCTAssertEqual(game.thunders.first?.level, 1)
        XCTAssertEqual(game.thunders.first?.duration, 4.096009)
        let enemyHealth = try XCTUnwrap(game.enemies.first).health
        try game.advance(by: 0.15, movement: .zero)
        XCTAssertLessThan(try XCTUnwrap(game.enemies.first).health, enemyHealth)
    }

    func testBankedExperienceMakesConsecutiveChoicesAndRanksStayCapped() throws {
        var game = try SurvivorBattle(seed: 723)
        for _ in 0..<150 {
            game.awardExperience(game.experienceNeeded)
            let choice = game.choices.contains(.thunder) ? SurvivorUpgrade.thunder : try XCTUnwrap(game.choices.first)
            XCTAssertTrue(game.choose(choice))
            while !game.choices.isEmpty { XCTAssertTrue(game.choose(try XCTUnwrap(game.choices.first))) }
        }
        XCTAssertEqual(game.rank(.thunder), 5)
        XCTAssertLessThanOrEqual(game.rank(.bubble), 5)
        game.awardExperience(game.experienceNeeded * 4)
        XCTAssertFalse(game.clock.running)
        XCTAssertTrue(game.choose(try XCTUnwrap(game.choices.first)))
        XCTAssertFalse(game.choices.isEmpty)
        XCTAssertFalse(game.clock.running)
        XCTAssertFalse(game.choices.contains(.thunder))
    }

    func testSnapshotRoundTripKeepsDeterministicCombat() throws {
        var original = try SurvivorBattle(seed: 904)
        try original.advance(by: 2, movement: .init(x: 1, y: 0))
        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(SurvivorBattle.self, from: data)
        try original.advance(by: 1, movement: .init(x: 0, y: 1))
        try restored.advance(by: 1, movement: .init(x: 0, y: 1))
        XCTAssertEqual(original.player, restored.player)
        XCTAssertEqual(original.clock, restored.clock)
        XCTAssertEqual(original.enemies.map(\.position), restored.enemies.map(\.position))
        XCTAssertEqual(original.health, restored.health)
    }

    func testVictoryAndDefeatStopCombat() throws {
        let config = SurvivorRunConfiguration(duration: 0.2, stages: [
            .init(id: "test", startsAt: 0, endsAt: 0.2, spawnInterval: 2, enemyLimit: 1)])
        var winner = try SurvivorBattle(configuration: config)
        try winner.advance(by: .greatestFiniteMagnitude, movement: .zero)
        XCTAssertEqual(winner.outcome, .victory)
        XCTAssertEqual(winner.clock.elapsed, 0.2)
        var loser = try SurvivorBattle()
        loser.takeDamage(100)
        try loser.advance(by: 0.1, movement: .zero)
        XCTAssertEqual(loser.outcome, .defeat)
        let elapsed = loser.clock.elapsed
        try loser.advance(by: 30, movement: .init(x: 1, y: 0))
        XCTAssertEqual(loser.clock.elapsed, elapsed)
    }

    func testInvalidInputsAreRejected() throws {
        var game = try SurvivorBattle()
        XCTAssertThrowsError(try game.advance(by: .infinity, movement: .zero))
        XCTAssertThrowsError(try game.advance(by: 1, movement: .init(x: .nan, y: 0)))
        XCTAssertThrowsError(try SurvivorBattle(thunderDuration: 21))
    }
}
