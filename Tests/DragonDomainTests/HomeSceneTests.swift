import Foundation
import XCTest
@testable import DragonDomain

final class HomeSceneTests: XCTestCase {
    private func clip(names: [String] = ["a", "b", "c"], starts: [Double] = [0, 16.666667, 50]) -> HomeSceneAnimation {
        HomeSceneAnimation(id: "test", characterID: "dafeiyu", title: "窗边", frameCount: 3,
            frameSize: [1030, 1200], durationMs: 100, frameNames: names,
            frameStartMs: starts, frameDurationsMs: [16.666667, 33.333333, 50])
    }

    func testPTSBasedPlaybackKeepsLongIntervalAndLastFrame() {
        let clip = clip()
        XCTAssertTrue(clip.isValid)
        XCTAssertEqual(clip.frameIndex(elapsed: -1), 0)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.02), 1)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.049), 1)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.05), 2)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.099), 2)
        XCTAssertEqual(clip.frameIndex(elapsed: 10), 2) // No silent hard loop.
    }

    func testMissingFramesUnsafeNamesAndBrokenTimingAreRejected() {
        XCTAssertFalse(clip(names: ["a", "b"]).isValid)
        XCTAssertFalse(clip(names: ["a", "../b", "c"]).isValid)
        XCTAssertFalse(clip(names: ["a", "a", "c"]).isValid)
        XCTAssertFalse(clip(starts: [0, 50, 16]).isValid)
        XCTAssertFalse(clip(starts: [0, .nan, 50]).isValid)
    }

    func testHomeLineHasNoChatHistoryImagesOrToolPermissions() throws {
        let fish = CompanionCharacter.xiaobai // request logic is role-independent
        var configuration = AIChatPreferences()
        var profile = AICharacterProfile.standard(for: fish)
        profile.contextRounds = 100; profile.appControl = true; profile.automaticStickers = true
        profile.thinking = true; profile.personality = "沿用角色性格"
        configuration.characters[fish.id] = profile
        let request = HomeGreeting.request(character: fish, configuration: configuration)
        XCTAssertTrue(request.history.isEmpty)
        XCTAssertTrue(request.imageURLs.isEmpty)
        XCTAssertTrue(request.stickers.isEmpty)
        XCTAssertEqual(request.profile?.personality, "沿用角色性格")
        XCTAssertEqual(request.profile?.contextRounds, 0)
        XCTAssertEqual(request.profile?.appControl, false)
        XCTAssertEqual(request.profile?.automaticStickers, false)
        XCTAssertEqual(request.profile?.thinking, false)
        XCTAssertEqual(configuration.profile(for: fish).contextRounds, 100) // No saved preference mutation.
        try request.profile?.validate()
    }

    func testHomeLineEnforcesTwentyCharactersIncludingEmoji() throws {
        let line = try HomeGreeting.text("  今天也想陪着你！👨‍👩‍👧‍👦这里是一段超过二十个字符的测试台词。\n谢谢  ")
        XCTAssertLessThanOrEqual(line.count, 20)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("👨‍👩‍👧‍👦"))
        XCTAssertThrowsError(try HomeGreeting.text(" \n\t "))
    }
}
