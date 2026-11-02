import XCTest
@testable import DragonDomain
final class SurvivorHD2DTests: XCTestCase {
    private func game() throws -> SurvivorBattle {
        var game=try SurvivorBattle(seed:71)
        let skill=PixelFXSkill(localLevels:[.init(level:1,clipID:"fireball-lv1",duration:1.3,loop:false)],role:"attack",id:"fireball",title:"火球",category:"fire",categoryTitle:"火",profile:.projectile,loop:false,duration:1.3,description:"")
        try game.configurePixelFX([skill],starter:"fireball");return game
    }
    func testCastWaitsForReleaseAndOnlyEmitsOneIndependentProjectile() throws {
        var game=try game();game.spawnEnemy(at:.init(x:300,y:0),kind:.boss)
        let id=try XCTUnwrap(game.enemies.first?.variant)
        game.configureHD2D([.init(id:id,duration:0.8,release:0.4,kind:"cast",effect:"curse-bolt")])
        for _ in 0..<500 where game.enemies.first?.actionStarted == nil { try game.advance(by:0.01,movement:.zero) }
        let start=try XCTUnwrap(game.enemies.first?.actionStarted)
        XCTAssertTrue((game.monsterShots ?? []).isEmpty)
        try game.advance(by:0.3,movement:.zero);XCTAssertTrue((game.monsterShots ?? []).isEmpty)
        try game.advance(by:0.15,movement:.zero)
        XCTAssertEqual(game.monsterShots?.count,1);XCTAssertEqual(game.monsterShots?.first?.effect,"curse-bolt")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(game.monsterShots?.first?.born),start+0.4-0.001)
        try game.advance(by:0.1,movement:.zero);XCTAssertEqual(game.monsterShots?.count,1)
        let saved=try JSONEncoder().encode(game);let restored=try JSONDecoder().decode(SurvivorBattle.self,from:saved)
        XCTAssertEqual(restored.hd2dMonsters?.count,1);XCTAssertEqual(restored.monsterShots?.first?.effect,"curse-bolt")
    }
    func testDeathsAreSeparateFromLiveEnemiesAndExpire() throws {
        var game=try game();game.spawnEnemy(at:.init(x:35,y:0),kind:.demon)
        let victim=try XCTUnwrap(game.enemies.first)
        game.configureHD2D([.init(id:try XCTUnwrap(victim.variant),duration:0.8,release:0.4,kind:"cast",effect:"curse-bolt")])
        for _ in 0..<600 where !(game.hd2dDeaths ?? []).contains(where:{$0.id==victim.id}) {try game.advance(by:0.01,movement:.zero)}
        XCTAssertTrue((game.hd2dDeaths ?? []).contains(where:{$0.id==victim.id}));XCTAssertFalse(game.enemies.contains(where:{$0.id==victim.id}))
        try game.advance(by:0.7,movement:.zero);XCTAssertFalse((game.hd2dDeaths ?? []).contains(where:{$0.id==victim.id}))
    }
}
