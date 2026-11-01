import Foundation
import XCTest
@testable import DragonDomain

final class PixelFXBattleTests: XCTestCase {
    private func catalog(_ count: Int = 10) -> [PixelFXSkill] {
        (0..<count).map { .init(id:"spell-\($0)",title:"Spell \($0)",category:"fire",categoryTitle:"火焰",
            profile:.projectile,loop:true,duration:1.2,description:"fixture") }
    }
    func testPixelFXModeDisablesRetiredWeaponsAndAutoAttacks() throws {
        var game = try SurvivorBattle(seed:4)
        try game.configurePixelFX(catalog(),starter:"spell-0")
        XCTAssertEqual(game.rank(.bubble),0); XCTAssertEqual(game.rank(.thunder),0)
        game.spawnEnemy(at:.init(x:120,y:0),kind:.demon)
        try game.advance(by:1.6,movement:.zero)
        XCTAssertTrue(game.bubbles.isEmpty); XCTAssertTrue(game.thunders.isEmpty)
        XCTAssertGreaterThan(game.kills,0)
        XCTAssertTrue(game.choices.allSatisfy { $0 != .bubble && $0 != .thunder })
    }
    func testWholePoolSelectableButOnlySixEquippedAndFiveLevels() throws {
        var game = try SurvivorBattle()
        try game.configurePixelFX(catalog(),starter:"spell-0")
        for index in 1..<6 {
            game.awardExperience(game.experienceNeeded)
            XCTAssertTrue(game.choosePixelFXFromLibrary("spell-\(index)"))
        }
        game.awardExperience(game.experienceNeeded)
        XCTAssertFalse(game.choosePixelFXFromLibrary("spell-6"))
        XCTAssertTrue(game.choosePixelFXFromLibrary("spell-0"))
        for _ in 0..<3 { game.awardExperience(game.experienceNeeded); XCTAssertTrue(game.choosePixelFXFromLibrary("spell-0")) }
        game.awardExperience(game.experienceNeeded)
        XCTAssertFalse(game.choosePixelFXFromLibrary("spell-0"))
        XCTAssertEqual(game.rank(.effect("spell-0")),5)
        XCTAssertEqual(game.pixelFX?.pool.count,10)
    }
    func testPausedPixelCombatAndModernSnapshotResume() throws {
        var game = try SurvivorBattle(seed:77)
        try game.configurePixelFX(catalog(),starter:"spell-0")
        game.spawnEnemy(at:.init(x:260,y:0),kind:.boss)
        try game.advance(by:0.4,movement:.zero)
        game.pause(.background)
        let age = game.pixelFX?.casts.first?.age
        try game.advance(by:120,movement:.init(x:1,y:0))
        XCTAssertEqual(game.pixelFX?.casts.first?.age,age)
        var restored = try JSONDecoder().decode(SurvivorBattle.self,from:JSONEncoder().encode(game))
        game.resume(.background); restored.resume(.background)
        try game.advance(by:0.4,movement:.zero); try restored.advance(by:0.4,movement:.zero)
        XCTAssertEqual(game.kills,restored.kills)
        XCTAssertEqual(game.enemies.map(\.health),restored.enemies.map(\.health))
        XCTAssertEqual(game.pixelFX?.casts.map(\.position),restored.pixelFX?.casts.map(\.position))
    }
    func testLegacySnapshotWithoutPixelStateStillDecodesAndMigrates() throws {
        var old = try SurvivorBattle()
        old.awardExperience(old.experienceNeeded); XCTAssertTrue(old.choose(.thunder))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as? [String:Any])
        object.removeValue(forKey:"pixelFX")
        var decoded = try JSONDecoder().decode(SurvivorBattle.self,from:JSONSerialization.data(withJSONObject:object))
        try decoded.configurePixelFX(catalog(),starter:"spell-2")
        XCTAssertEqual(decoded.level,old.level)
        XCTAssertEqual(decoded.clock.elapsed,old.clock.elapsed)
        XCTAssertEqual(decoded.rank(.effect("spell-2")),1)
        XCTAssertEqual(decoded.rank(.thunder),0)
    }
    func testInvalidCatalogIsRejected() throws {
        var game = try SurvivorBattle()
        XCTAssertThrowsError(try game.configurePixelFX([],starter:"missing"))
        XCTAssertThrowsError(try game.configurePixelFX(catalog(),starter:"missing"))
        XCTAssertThrowsError(try game.configurePixelFX(catalog()+catalog(),starter:"spell-0"))
    }
}
