import XCTest

final class ChatInterfaceTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-chat", "--appearance-light", "--chat-test-store", UUID().uuidString]
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
        XCTAssertTrue(app.staticTexts["聊天功能测试中"].waitForExistence(timeout: 5))
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
}
