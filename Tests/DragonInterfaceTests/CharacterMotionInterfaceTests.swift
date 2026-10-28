import XCTest

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

    func testSeparateDailyActionSwitchesAndRealVideoPlayback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu", "--preview-tasks", "--appearance-light"]
        app.launch()
        XCTAssertTrue(app.buttons["dailyMotion_pet_walk"].waitForExistence(timeout: 10))
        app.buttons["dailyMotion_pet_walk"].tap()
        capture(app, "dafeiyu-dog-image-sequence")
        app.buttons["dailyMotion_pet_walk_video"].tap()
        let video = app.descendants(matching: .any).matching(identifier: "dogWalkVideoStage").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        expectation(for: NSPredicate(format: "value == %@", "正在播放"), evaluatedWith: video)
        waitForExpectations(timeout: 12)
        capture(app, "dafeiyu-dog-real-video")
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
        app.buttons["characterMotionSettings"].tap()
        XCTAssertTrue(app.buttons["dailyMotion_ride"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["dailyMotion_ride"].label, "御剑")
        XCTAssertFalse(app.buttons["dailyMotion_pet_walk"].exists)
        reveal(app.switches["dailyMotionToggle_ride"], in: app)
        capture(app, "xiaobai-sword-independent-motion-switch")
    }
}
