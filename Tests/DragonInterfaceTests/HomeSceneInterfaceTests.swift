import XCTest

final class HomeSceneInterfaceTests: XCTestCase {
    func testFullHomeSceneCompletesReplaysAndKeepsShortNativeDialogue() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu", "--appearance-light", "--chat-test-store", UUID().uuidString]
        app.launch()
        let stage = app.images["homeScenePlayback"]
        XCTAssertTrue(stage.waitForExistence(timeout: 12))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "dafeiyu-native-home-scene"
        attachment.lifetime = .keepAlways
        add(attachment)
        expectation(for: NSPredicate(format: "value == %@", "播放完成"), evaluatedWith: stage)
        waitForExpectations(timeout: 8)
        app.buttons["worldCharacterGreeting"].tap()
        let line = app.staticTexts["homeCharacterDialogue"]
        expectation(for: NSPredicate(format: "label == %@", "聊天功能测试中"), evaluatedWith: line)
        waitForExpectations(timeout: 5)
        XCTAssertLessThanOrEqual(line.label.count, 20)
        XCTAssertEqual(stage.value as? String, "正在播放")
        app.buttons["homeShortcut-actions"].tap()
        XCTAssertTrue(app.buttons["dailyMotion_pet_walk"].waitForExistence(timeout: 8))
        app.buttons["closeHomePanel"].tap()
        app.tabBars.buttons["聊天"].tap()
        app.tabBars.buttons["我的世界"].tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
    }
}
