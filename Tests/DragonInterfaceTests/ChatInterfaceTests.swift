import XCTest

final class ChatInterfaceTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--preview-chat", "--appearance-light", "--chat-test-store", UUID().uuidString]
        app.launch()
        return app
    }

    private func create(_ app: XCUIApplication, group: Bool) {
        app.buttons[group ? "startGroupChat" : "startDirectChat"].tap()
        XCTAssertTrue(app.buttons["chatSelect-xiaobai"].waitForExistence(timeout: 5))
        if group {
            let field = app.textFields["chatGroupName"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("Our group")
        }
        capture(app, name: group ? "chat-group-create" : "chat-character-picker")
        app.buttons["chatSelect-xiaobai"].tap()
        if group { app.buttons["chatSelect-dafeiyu"].tap() }
        app.buttons["saveChat"].tap()
        XCTAssertTrue(input(app).waitForExistence(timeout: 5))
    }

    private func input(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "chatInput").firstMatch
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func send(_ app: XCUIApplication, _ text: String) {
        let field = input(app)
        field.tap()
        field.typeText(text)
        app.buttons["sendChat"].tap()
        XCTAssertTrue(app.staticTexts["聊天功能测试中"].firstMatch.waitForExistence(timeout: 5))
    }

    func testDirectChatRepliesAndRestoresHistoryWithoutDuplicateConversation() {
        let app = launch()
        create(app, group: false)
        XCTAssertFalse(app.buttons["sendChat"].isEnabled, "Empty messages cannot be sent")
        send(app, "Hello Xiaobai")
        app.terminate()
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        capture(app, name: "chat-conversation-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Hello Xiaobai"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["聊天功能测试中"].exists)
        capture(app, name: "chat-direct-reply-restored")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["newChat"].tap()
        app.buttons["和角色聊天"].tap()
        app.buttons["chatSelect-xiaobai"].tap()
        app.buttons["saveChat"].tap()
        XCTAssertTrue(app.staticTexts["Hello Xiaobai"].waitForExistence(timeout: 5))
    }

    func testGroupCanBeCreatedRenamedAndCleared() {
        let app = launch()
        create(app, group: true)
        send(app, "Hello group")
        expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: app.staticTexts.matching(NSPredicate(format: "label == %@", "聊天功能测试中")))
        waitForExpectations(timeout: 5)
        capture(app, name: "chat-group-reply")
        app.buttons["chatSettings"].tap()
        app.buttons["管理群组"].tap()
        let name = app.textFields["chatGroupName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture(app, name: "chat-group-members")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Our group".count) + "New group")
        app.buttons["saveChat"].tap()
        XCTAssertTrue(app.navigationBars["New group"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hello group"].exists, "Editing group preserves history")
        capture(app, name: "chat-group-renamed")
        app.buttons["chatSettings"].tap()
        app.buttons["清空聊天记录"].tap()
        app.buttons["清空记录"].tap()
        XCTAssertTrue(app.staticTexts["打个招呼吧"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Hello group"].exists)
        capture(app, name: "chat-group-empty")
    }

    func testDafeiyuDirectChatUsesNormalAvatarAndRestores() {
        let app = launch()
        app.buttons["startDirectChat"].tap()
        XCTAssertTrue(app.buttons["chatSelect-dafeiyu"].waitForExistence(timeout: 5))
        capture(app, name: "dafeiyu-normal-avatar-picker")
        app.buttons["chatSelect-dafeiyu"].tap()
        app.buttons["saveChat"].tap()
        XCTAssertTrue(input(app).waitForExistence(timeout: 5))
        send(app, "Hello Dafeiyu")
        capture(app, name: "dafeiyu-direct-reply")
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        XCTAssertTrue(app.navigationBars["大肥鱼"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hello Dafeiyu"].exists)
        XCTAssertTrue(app.staticTexts["聊天功能测试中"].exists)
    }

    func testDafeiyuWorldMotionGalleryAndNonVoiceReminder() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--appearance-light", "--character-dafeiyu"]
        app.launch()
        XCTAssertTrue(app.buttons["startCompanion"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["startCompanion"].label.contains("大肥鱼"))
        capture(app, name: "dafeiyu-world-standing")
        app.tabBars.buttons["角色"].tap()
        app.segmentedControls["characterBrowsingMode"].buttons["横向卡片"].tap()
        let quick = app.buttons["quickCharacter-dafeiyu"]
        if !quick.isHittable { app.swipeUp() }
        quick.tap()
        let card = app.buttons["characterCard-dafeiyu"]
        if !card.isHittable { app.swipeDown() }
        card.tap()
        XCTAssertTrue(app.buttons["characterMotionSettings"].waitForExistence(timeout: 5))
        capture(app, name: "dafeiyu-character-detail-motion-entry")
        app.buttons["characterMotionSettings"].tap()
        XCTAssertTrue(app.staticTexts["大肥鱼的日常"].waitForExistence(timeout: 5))
        app.buttons["待机"].tap()
        capture(app, name: "dafeiyu-idle-preview")
        let actor = app.descendants(matching: .any).matching(identifier: "motionPreviewStage").firstMatch
        XCTAssertTrue(actor.waitForExistence(timeout: 5))
        actor.tap()
        XCTAssertTrue((actor.value as? String)?.contains("招呼") == true)
        capture(app, name: "dafeiyu-tap-reaction")
        app.buttons["右走"].tap()
        capture(app, name: "dafeiyu-walk-preview")
        app.buttons["打滚"].tap()
        capture(app, name: "dafeiyu-roll-preview")
        app.buttons["closeMotionSettings"].tap()
        app.buttons["closeCharacterDetail"].tap()
        app.tabBars.buttons["闹钟"].tap()
        XCTAssertTrue(app.buttons["newAlarm-dafeiyu"].waitForExistence(timeout: 5))
        app.buttons["newAlarm-dafeiyu"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alarmSystemSound").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveCharacterAlarm"].isEnabled)
        capture(app, name: "dafeiyu-system-tone-alarm")
        app.buttons["取消"].tap()
    }
}
