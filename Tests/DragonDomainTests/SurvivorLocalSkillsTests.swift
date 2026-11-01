import XCTest
@testable import DragonDomain

final class SurvivorLocalSkillsTests:XCTestCase {
    private func catalog()->[PixelFXSkill] {
        SurvivorLocalSkills.ids.map { id in
            PixelFXSkill(localLevels:(1...5).map{.init(level:$0,clipID:"\(id)-lv\($0)",duration:3.4,loop:id=="orbit-swords")},role:"attack",id:id,title:id,category:"local",categoryTitle:"确认素材",profile:id=="fireball" || id=="seeking-swords" ? .projectile:id=="orbit-swords" ? .orbit:.zone,loop:id=="orbit-swords",duration:3.4,description:"")
        }
    }
    private func game(_ starter:String) throws ->SurvivorBattle {
        var game=try SurvivorBattle(seed:11)
        try game.configurePixelFX(catalog(),starter:starter)
        return game
    }
    func testFireballUsesNativeProjectileModuleAndFiveIndependentShots() throws {
        var game=try game("fireball")
        for _ in 0..<4 { game.awardExperience(game.experienceNeeded);XCTAssertTrue(game.choosePixelFXFromLibrary("fireball")) }
        game.spawnEnemy(at:.init(x:300,y:0),kind:.boss)
        try game.advance(by:0.01,movement:.zero)
        XCTAssertEqual(game.pixelFX?.casts.filter{$0.skillID=="fireball"}.count,5)
        XCTAssertTrue(game.pixelFX!.casts.allSatisfy{$0.clipID=="fireball-flight"})
        XCTAssertTrue(game.bubbles.isEmpty);XCTAssertTrue(game.thunders.isEmpty)
        XCTAssertTrue(game.enemies.allSatisfy{$0.variant?.hasPrefix("skeleton-")==true})
    }
    func testOrbitPersistsAndSupportDoesNotConsumeAttackSlots() throws {
        var game=try game("orbit-swords")
        try game.advance(by:8,movement:.zero)
        XCTAssertEqual(game.pixelFX?.casts.filter{$0.skillID=="orbit-swords"}.count,1)
        XCTAssertGreaterThan(game.pixelFX!.casts[0].duration,1200)
        let speed=game.playerSpeed
        game.awardExperience(game.experienceNeeded);XCTAssertTrue(game.chooseLocalSupport(.stride))
        XCTAssertGreaterThan(game.playerSpeed,speed)
        XCTAssertEqual(game.equippedPixelSkills.count,1)
        game.awardExperience(game.experienceNeeded);XCTAssertTrue(game.chooseLocalSupport(.defense))
        let health=game.health;game.takeDamage(8)
        XCTAssertEqual(game.health,health-6)
        game.awardExperience(game.experienceNeeded);XCTAssertTrue(game.chooseLocalSupport(.vitality))
        XCTAssertEqual(game.maximumHealth,120)
    }
    func testLightningWaitsForImpactAndTargetsWithinSelectionRadius() throws {
        var game=try game("lightning")
        game.spawnEnemy(at:.init(x:200,y:0),kind:.boss)
        let initial=game.enemies[0].health
        try game.advance(by:0.2,movement:.zero)
        XCTAssertEqual(game.enemies[0].health,initial)
        try game.advance(by:0.35,movement:.zero)
        XCTAssertLessThan(game.enemies[0].health,initial)
    }
    func testFiveLightningChannelsRemainFiveWithOnlyOneEnemy() throws {
        var game=try game("lightning")
        for _ in 0..<4 {game.awardExperience(game.experienceNeeded);XCTAssertTrue(game.choosePixelFXFromLibrary("lightning"))}
        game.spawnEnemy(at:.init(x:200,y:0),kind:.boss)
        try game.advance(by:0.01,movement:.zero)
        XCTAssertEqual(game.pixelFX?.casts.filter{$0.skillID=="lightning"}.count,5)
    }
    func testScriptedEnemyCannotSpawnOutsideFiniteWorld() throws {
        var game=try game("fireball")
        game.spawnEnemy(at:.init(x:1e9,y:1e9),kind:.boss)
        XCTAssertLessThan(game.enemies[0].position.x,SurvivorGrassland.halfSide)
        XCTAssertLessThan(game.enemies[0].position.y,SurvivorGrassland.halfSide)
    }
    func testFiniteSquareAndMonotonicCrowdPressure() throws {
        let p=SurvivorGrassland.clamp(.init(x:1e9,y:-1e9))
        XCTAssertEqual(p.x,-p.y)
        XCTAssertLessThan(p.x,SurvivorGrassland.halfSide)
        let stages=SurvivorRunConfiguration.standard.stages
        XCTAssertEqual(stages.last?.enemyLimit,320)
        for pair in zip(stages,stages.dropFirst()) {
            XCTAssertGreaterThan(pair.1.enemyLimit,pair.0.enemyLimit)
            XCTAssertLessThan(pair.1.spawnInterval,pair.0.spawnInterval)
        }
    }
    func testLocalSnapshotRetainsVariantAndNativeCast() throws {
        var game=try game("fireball")
        game.spawnEnemy(at:.init(x:400,y:0),kind:.boss)
        try game.advance(by:0.1,movement:.zero)
        let copy=try JSONDecoder().decode(SurvivorBattle.self,from:JSONEncoder().encode(game))
        XCTAssertEqual(copy.enemies.first?.variant,game.enemies.first?.variant)
        XCTAssertEqual(copy.pixelFX?.casts.first?.clipID,"fireball-flight")
        XCTAssertTrue(copy.usesLocalSkills)
    }
}
