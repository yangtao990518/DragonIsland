import Foundation
import XCTest
@testable import DragonDomain

final class CharacterArtworkTests: XCTestCase {
    private func resident(_ id: String) -> CompanionCharacter {
        var c = CompanionCharacter(id: id, name: id, subtitle: "", introduction: "", origin: "",
                                   chibiAsset: "Chibi", portraitAsset: "Portrait", heroAsset: "Hero",
                                   chibiSource: "chibi.png", standingSource: "standing.png")
        c.artworks = [CharacterArtwork(id: "photo", title: "照片", asset: id + "Photo", source: id + ".png")]
        return c
    }
    func testSelectionsAreIndependentAndPersistAcrossReload() {
        let suite = "artwork-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = resident("a"), b = resident("b")
        var preferences = CharacterArtworkPreferences()
        preferences.select("photo", for: a); preferences.save(to: defaults)
        let restored = CharacterArtworkPreferences.load(from: defaults)
        XCTAssertEqual(restored.selected(for: a).asset, "aPhoto")
        XCTAssertEqual(restored.selected(for: b).id, "default")
        XCTAssertEqual(a.avatarAsset, "PortraitAvatar")
        XCTAssertEqual(a.chibiAsset, "Chibi")
    }
    func testMissingOrRemovedArtworkFallsBackAndInvalidSelectionIsIgnored() {
        let character = resident("a")
        var preferences = CharacterArtworkPreferences(selections: ["a": "removed"])
        XCTAssertEqual(preferences.selected(for: character).id, "default")
        preferences.select("photo", for: character)
        preferences.select("unknown", for: character)
        XCTAssertEqual(preferences.selected(for: character).id, "photo")
        preferences.select("default", for: character)
        XCTAssertEqual(preferences.selected(for: character).asset, "Hero")
    }
}
