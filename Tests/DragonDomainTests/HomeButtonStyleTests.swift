import Foundation
import XCTest
@testable import DragonDomain

final class HomeButtonStyleTests: XCTestCase {
    func testEachResidentKeepsTheirOwnStyleAfterReload() {
        let suite = "home-buttons-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = CharacterHomeButtonPreferences()
        settings.select(.candy, for: "dafeiyu")
        settings.select(.fantasy, for: "xiaobai")
        settings.save(to: defaults)
        var restored = CharacterHomeButtonPreferences.load(from: defaults)
        XCTAssertEqual(restored.style(for: "dafeiyu"), .candy)
        XCTAssertEqual(restored.style(for: "xiaobai"), .fantasy)
        restored.select(.candy, for: "xiaobai")
        restored.select(.fantasy, for: "dafeiyu")
        XCTAssertEqual(restored.style(for: "xiaobai"), .candy)
        XCTAssertEqual(restored.style(for: "dafeiyu"), .fantasy)
        XCTAssertEqual(restored.style(for: "future-character"), .fantasy)
    }

    func testUnknownRemovedThemeDoesNotResetAnotherCharacter() throws {
        let data = Data(#"{"selections":{"xiaobai":"removed","dafeiyu":"candy"}}"#.utf8)
        let settings = try JSONDecoder().decode(CharacterHomeButtonPreferences.self, from: data)
        XCTAssertEqual(settings.style(for: "xiaobai"), .fantasy)
        XCTAssertEqual(settings.style(for: "dafeiyu"), .candy)
    }
}
