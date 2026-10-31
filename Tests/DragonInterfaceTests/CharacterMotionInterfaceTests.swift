import XCTest
import CoreGraphics

final class CharacterMotionInterfaceTests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    // The native preview choices now form a horizontal rail.
    private func selectPreview(_ action: String, in app: XCUIApplication) {
        let target = app.buttons["dailyMotion_\(action)"]
        let anchor = app.buttons["dailyMotion_random"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if target.isHittable { target.tap(); return }
            let y = anchor.frame.midY - app.frame.minY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0)).withOffset(CGVector(dx: 0, dy: y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0)).withOffset(CGVector(dx: 0, dy: y))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTFail("Preview action is not reachable: \(action)")
    }
    func testWorldPhotoSelectionPersistsWithoutChangingOtherCharacter() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu", "--preview-characters", "--appearance-light"]
        app.launch()
        app.segmentedControls["characterBrowsingMode"].buttons["横向卡片"].tap()
        let quick = app.buttons["quickCharacter-dafeiyu"]
        reveal(quick, in: app); quick.tap(); app.swipeDown()
        app.buttons["characterCard-dafeiyu"].tap()
        let photo = app.buttons["worldArtwork_sea-breeze"]
        XCTAssertTrue(photo.waitForExistence(timeout: 8)); photo.tap()
        capture(app, "dafeiyu-world-photo-picker")
        app.buttons["closeCharacterDetail"].tap()
        app.tabBars.buttons["我的世界"].tap()
        XCTAssertEqual(app.buttons["worldCharacterCard"].value as? String, "sea-breeze")
        capture(app, "dafeiyu-world-selected-photo")
        app.terminate(); app.launch(); app.tabBars.buttons["我的世界"].tap()
        XCTAssertEqual(app.buttons["worldCharacterCard"].value as? String, "sea-breeze")
        app.buttons["worldCharacterCard"].tap()
        app.buttons["worldArtwork_default"].tap()
    }

    func testFullDanceActionsAndIndependentSwitches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu", "--preview-tasks", "--appearance-light"]
        app.launch()
        for id in ["dance1", "dance2"] {
            selectPreview(id, in: app)
            let stage = app.descendants(matching: .any).matching(identifier: "fullVideoActionStage").firstMatch
            XCTAssertTrue(stage.waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["完整片段 · 12.10 秒"].exists)
            capture(app, "dafeiyu-\(id)-full-source-preview")
            expectation(for: NSPredicate(format: "value == %@", "播放完成"), evaluatedWith: stage)
            waitForExpectations(timeout: 16)
            app.buttons["replayFullVideoAction"].tap()
            XCTAssertEqual(stage.value as? String, "正在播放")
        }
        let first = app.switches["dailyMotionToggle_dance1"], second = app.switches["dailyMotionToggle_dance2"]
        reveal(first, in: app)
        let original = second.value as? String
        first.tap()
        XCTAssertEqual(second.value as? String, original)
        let saved = first.value as? String
        app.terminate(); app.launch()
        reveal(app.switches["dailyMotionToggle_dance1"], in: app)
        XCTAssertEqual(app.switches["dailyMotionToggle_dance1"].value as? String, saved)
    }
    func testCharacterCardsAndQuickAvatarNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--preview-characters", "--appearance-light"]
        app.launch()
        app.segmentedControls["characterBrowsingMode"].buttons["横向卡片"].tap()
        let xiao = app.buttons["quickCharacter-xiaobai"]
        reveal(xiao, in: app); xiao.tap()
        app.swipeDown()
        XCTAssertTrue(app.buttons["characterCard-xiaobai"].waitForExistence(timeout: 8))
        capture(app, "characters-horizontal-xiaobai")
        let quick = app.buttons["quickCharacter-dafeiyu"]
        reveal(quick, in: app); quick.tap()
        let fish = app.buttons["characterCard-dafeiyu"]
        XCTAssertTrue(fish.waitForExistence(timeout: 5))
        capture(app, "characters-quick-avatar-dafeiyu")
        app.swipeDown()
        app.segmentedControls["characterBrowsingMode"].buttons["纵向列表"].tap()
        XCTAssertTrue(app.buttons["characterCard-xiaobai"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.segmentedControls["characterBrowsingMode"].buttons["纵向列表"].isSelected)
    }

    func testSeparateDailyActionSwitchesAndConfirmedDogPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu", "--preview-tasks", "--appearance-light"]
        app.launch()
        selectPreview("pet_walk", in: app)
        capture(app, "dafeiyu-dog-image-sequence")
        XCTAssertFalse(app.buttons["dailyMotion_pet_walk_video"].exists)
        let dog = app.switches["dailyMotionToggle_pet_walk"]
        reveal(dog, in: app)
        XCTAssertTrue(dog.exists)
        XCTAssertTrue(app.switches["dailyMotionToggle_ride"].exists)
        let originalDog = dog.value as? String
        let walk = app.switches["walkMotionToggle"]
        walk.tap()
        XCTAssertEqual(dog.value as? String, originalDog)
        dog.tap()
        let saved = dog.value as? String
        capture(app, "dafeiyu-independent-motion-switches")
        app.terminate(); app.launch()
        reveal(app.switches["dailyMotionToggle_pet_walk"], in: app)
        XCTAssertEqual(app.switches["dailyMotionToggle_pet_walk"].value as? String, saved)
        app.terminate()
        app.launchArguments = ["--maiverse-capture", "--preview-characters", "--appearance-light"]
        app.launch()
        app.segmentedControls["characterBrowsingMode"].buttons["横向卡片"].tap()
        let xiao = app.buttons["quickCharacter-xiaobai"]
        reveal(xiao, in: app); xiao.tap()
        app.swipeDown()
        app.buttons["characterCard-xiaobai"].tap()
        reveal(app.buttons["characterMotionSettings"], in: app)
        app.buttons["characterMotionSettings"].tap()
        XCTAssertTrue(app.buttons["dailyMotion_ride"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["dailyMotion_ride"].label, "御剑")
        XCTAssertFalse(app.buttons["dailyMotion_pet_walk"].exists)
        reveal(app.switches["dailyMotionToggle_ride"], in: app)
        capture(app, "xiaobai-sword-independent-motion-switch")
    }
}
