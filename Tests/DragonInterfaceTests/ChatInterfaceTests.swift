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
        XCTAssertTrue(app.staticTexts["���칦�ܲ�����"].firstMatch.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["���칦�ܲ�����"].exists)
        capture(app, name: "chat-direct-reply-restored")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["newChat"].tap()
        app.buttons["�ͽ�ɫ����"].tap()
        app.buttons["chatSelect-xiaobai"].tap()
        app.buttons["saveChat"].tap()
        XCTAssertTrue(app.staticTexts["Hello Xiaobai"].waitForExistence(timeout: 5))
    }

    func testGroupCanBeCreatedRenamedAndCleared() {
        let app = launch()
        create(app, group: true)
        send(app, "Hello group")
        expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: app.staticTexts.matching(NSPredicate(format: "label == %@", "���칦�ܲ�����")))
        waitForExpectations(timeout: 5)
        capture(app, name: "chat-group-reply")
        app.buttons["chatSettings"].tap()
        app.buttons["����Ⱥ��"].tap()
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
        app.buttons["��������¼"].tap()
        app.buttons["��ռ�¼"].tap()
        XCTAssertTrue(app.staticTexts["����к���"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.navigationBars["�����"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hello Dafeiyu"].exists)
        XCTAssertTrue(app.staticTexts["���칦�ܲ�����"].exists)
    }

    func testDafeiyuWorldMotionGalleryAndNonVoiceReminder() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--appearance-light", "--character-dafeiyu"]
        app.launch()
        XCTAssertTrue(app.buttons["startCompanion"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["startCompanion"].label.contains("�����"))
        capture(app, name: "dafeiyu-world-standing")
        for _ in 0..<4 {
            if app.buttons["worldMotionSettings"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["worldMotionSettings"].tap()
        XCTAssertTrue(app.staticTexts["�������ճ�"].waitForExistence(timeout: 5))
        app.buttons["����"].tap()
        capture(app, name: "dafeiyu-idle-preview")
        let actor = app.descendants(matching: .any).matching(identifier: "motionPreviewStage").firstMatch
        XCTAssertTrue(actor.waitForExistence(timeout: 5))
        actor.tap()
        XCTAssertTrue((actor.value as? String)?.contains("�к�") == true)
        capture(app, name: "dafeiyu-tap-reaction")
        app.buttons["����"].tap()
        capture(app, name: "dafeiyu-walk-preview")
        app.buttons["���"].tap()
        capture(app, name: "dafeiyu-roll-preview")
        app.buttons["���"].tap()
        app.tabBars.buttons["����"].tap()
        XCTAssertTrue(app.buttons["newAlarm-dafeiyu"].waitForExistence(timeout: 5))
        app.buttons["newAlarm-dafeiyu"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alarmSystemSound").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveCharacterAlarm"].isEnabled)
        capture(app, name: "dafeiyu-system-tone-alarm")
        app.buttons["ȡ��"].tap()
    }
}
