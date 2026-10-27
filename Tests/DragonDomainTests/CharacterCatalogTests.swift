import Foundation
import XCTest
@testable import DragonDomain

final class CharacterCatalogTests: XCTestCase {
    private func catalogData() throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Shared/Resources/Characters.json"))
    }

    func testProductionCatalogHasDistinctChibiAndStandingArt() throws {
        let characters = try CharacterCatalog.decode(catalogData())
        let first = try XCTUnwrap(characters.first)
        XCTAssertEqual(first.id, CompanionCharacter.xiaobai.id)
        XCTAssertEqual(first, .xiaobai)
        XCTAssertNotEqual(first.chibiAsset, first.portraitAsset)
        XCTAssertNotEqual(first.chibiSource, first.standingSource)
    }

    func testInvalidAndDuplicateCatalogEntriesAreRejected() throws {
        XCTAssertThrowsError(try CharacterCatalog.decode(Data("[]".utf8)))
        let duplicate = try JSONEncoder().encode([CompanionCharacter.xiaobai, .xiaobai])
        XCTAssertThrowsError(try CharacterCatalog.decode(duplicate))
    }

    func testDafeiyuHasIndependentNormalAvatarAndMotionNamespace() throws {
        let characters = try CharacterCatalog.decode(catalogData())
        let fish = try XCTUnwrap(characters.first { $0.id == "dafeiyu" })
        XCTAssertEqual(fish.name, "大肥鱼")
        XCTAssertEqual(CharacterCatalog.resolve("dafeiyu", in: characters), fish)
        XCTAssertEqual(fish.avatarAsset, "DafeiyuStandingAvatar")
        XCTAssertNotEqual(fish.avatarAsset, fish.chibiAsset)
        let motion = try XCTUnwrap(fish.motionProfile)
        XCTAssertNotEqual(motion.fontPrefix, CompanionCharacter.xiaobai.motionProfile?.fontPrefix)
        XCTAssertNotEqual(motion.timelineResource, CompanionCharacter.xiaobai.motionProfile?.timelineResource)
        XCTAssertNotEqual(motion.assetPrefix, CompanionCharacter.xiaobai.motionProfile?.assetPrefix)
    }

    func testLegacyAndUnknownCharacterIDsResolveSafely() {
        XCTAssertEqual(CharacterCatalog.resolve(nil, in: [.xiaobai]), .xiaobai)
        XCTAssertEqual(CharacterCatalog.resolve("removed-character", in: [.xiaobai]), .xiaobai)
        XCTAssertEqual(CharacterCatalog.resolve("xiaobai", in: []), .xiaobai)
    }
}

