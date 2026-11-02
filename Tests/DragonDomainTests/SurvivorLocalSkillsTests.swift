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

    func testWarmPlanIncludesCurrentNextAndUnlearnedEntryWithoutAllFiveLevels() {
        let ids=Set(SurvivorLocalSkills.warmClipIDs(skills:catalog(),ranks:["fireball":1]))
        XCTAssertEqual(ids.count,9)
        XCTAssertTrue(ids.contains("fireball-lv1"));XCTAssertTrue(ids.contains("fireball-lv2"))
        XCTAssertTrue(ids.contains("boulder-lv1"))
        XCTAssertFalse(ids.contains("fireball-lv3"))
    }

    func testWarmPlanReleasesRetiredLevelAndNeverRequestsLevelSix() {
        let ids=Set(SurvivorLocalSkills.warmClipIDs(skills:catalog(),ranks:["fireball":4,"boulder":5]))
        XCTAssertTrue(ids.contains("fireball-lv4"));XCTAssertTrue(ids.contains("fireball-lv5"))
        XCTAssertTrue(ids.contains("boulder-lv5"))
        XCTAssertFalse(ids.contains("fireball-lv2"));XCTAssertFalse(ids.contains("boulder-lv6"))
    }

    func testEntrySkeletonSurvivesTwoFireballsAndDiesOnThird() throws {
        var game = try game("fireball")
        game.spawnEnemy(at: .init(x: 200, y: 0), kind: .demon)
        let damage = SurvivorLocalSkills.baseDamage("fireball", level: 1)
        game.damageEnemy(at: 0, damage: damage)
        game.damageEnemy(at: 0, damage: damage)
        XCTAssertGreaterThan(game.enemies[0].health, 0)
        game.damageEnemy(at: 0, damage: damage)
        XCTAssertEqual(game.enemies[0].health, 0)
        let count = game.combatHits?.count
        game.damageEnemy(at: 0, damage: damage)
        XCTAssertEqual(game.combatHits?.count, count, "Dead targets cannot emit repeated hits")
        try game.advance(by: 0.01, movement: .zero)
        XCTAssertEqual(game.kills, 1)
        XCTAssertEqual(game.drops.count, 1)
    }

    func testConfirmedEliteAndBossHaveMoreHealthWithoutChangingArchivedBalance() throws {
        var game = try game("fireball")
        game.spawnEnemy(at: .init(x: 300, y: 0), kind: .elite)
        game.spawnEnemy(at: .init(x: -300, y: 0), kind: .boss)
        XCTAssertEqual(game.enemies.map(\.maximumHealth), [480, 3200])
        var archived = try SurvivorBattle()
        archived.spawnEnemy(at: .zero, kind: .demon)
        XCTAssertEqual(archived.enemies[0].health, 30)
    }

    func testNonlethalProjectileHitEmitsFeedbackAndStartsRedFlash() throws {
        var game = try game("fireball")
        let id = game.spawnEnemy(at: .init(x: 120, y: 0), kind: .demon)
        try game.advance(by: 0.35, movement: .zero)
        let target = try XCTUnwrap(game.enemies.first { $0.id == id })
        XCTAssertGreaterThan(target.health, 0)
        XCTAssertLessThan(target.health, target.maximumHealth)
        XCTAssertGreaterThan(target.hitUntil, game.clock.elapsed)
        XCTAssertTrue(game.combatHits?.contains { $0.enemyID == id && $0.damage == 34 } == true)
    }

    func testPlayerFlashExpiresBeforeInvulnerabilityAndBlockedHitsDoNotRestartIt() throws {
        var game = try game("fireball")
        game.takeDamage(8)
        XCTAssertEqual(game.playerHitRemaining, 0.18, accuracy: 0.0001)
        let hitID = game.combatHits?.last?.id
        try game.advance(by: 0.2, movement: .zero)
        XCTAssertEqual(game.playerHitRemaining, 0)
        XCTAssertTrue(game.playerIsInvincible)
        game.takeDamage(8)
        XCTAssertEqual(game.health, 92)
        XCTAssertEqual(game.combatHits?.last?.id, hitID)
        try game.advance(by: 0.51, movement: .zero)
        game.takeDamage(8)
        XCTAssertEqual(game.health, 84)
        XCTAssertGreaterThan(game.playerHitRemaining, 0)
    }

    func testHitEventsAreBoundedExpireAndDoNotApplyDamageWhilePaused() throws {
        var game = try game("fireball")
        game.spawnEnemy(at: .init(x: 600, y: 0), kind: .boss)
        for _ in 0..<100 { game.damageEnemy(at: 0, damage: 1) }
        XCTAssertEqual(game.combatHits?.count, 48)
        game.pause(.menu)
        game.damageEnemy(at: 0, damage: 10)
        XCTAssertEqual(game.enemies[0].health, 3100)
        game.resume(.menu)
        game.damageEnemy(at: -1, damage: 10)
        game.damageEnemy(at: 0, damage: .nan)
        game.damageEnemy(at: 0, damage: -2)
        XCTAssertEqual(game.enemies[0].health, 3100)
        try game.advance(by: 0.5, movement: .zero)
        XCTAssertTrue(game.combatHits?.isEmpty == true)
    }

    func testHitFeedbackRoundTripAndOldSaveWithoutEventsStillLoads() throws {
        var game = try game("fireball")
        game.takeDamage(8)
        let data = try JSONEncoder().encode(game)
        let copy = try JSONDecoder().decode(SurvivorBattle.self, from: data)
        XCTAssertEqual(copy.combatHits?.last?.damage, 8)
        XCTAssertEqual(copy.playerHitRemaining, game.playerHitRemaining)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "combatHits")
        let old = try JSONDecoder().decode(SurvivorBattle.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.combatHits)
        XCTAssertEqual(old.health, 92)
    }

    func testNaturalWaveSpawnsBeyondTheZoomedOutBattleView() throws {
        var game=try game("fireball")
        game.setViewport(width:844,height:390)
        try game.advance(by:0.6,movement:.zero)
        XCTAssertEqual(game.enemies.count,3)
        for enemy in game.enemies {
            XCTAssertFalse(SurvivorViewport.contains(enemy.position,player:game.player,width:844,height:390))
        }
        let restored=try JSONDecoder().decode(SurvivorBattle.self,from:JSONEncoder().encode(game))
        XCTAssertEqual(restored.cameraViewport,.init(x:844,y:390))
    }
}
