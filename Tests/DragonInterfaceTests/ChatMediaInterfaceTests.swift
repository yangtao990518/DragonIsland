import XCTest

final class ChatMediaInterfaceTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--chat-media-tools-tests", "--preview-chat", "--appearance-light", "--chat-test-store", UUID().uuidString]
        app.launch()
        openChat(app)
        return app
    }
    private func openChat(_ app: XCUIApplication) {
        let chat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat-")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 12)); chat.tap()
        XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout: 5))
    }
    private func send(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["chatInput"]
        input.tap(); input.typeText(text)
        app.buttons["sendChat"].tap()
    }
    func testImageOnlySendAndMessagesSurviveRelaunch() {
        let app = launch()
        XCTAssertTrue(app.buttons["chatImageAttachment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sendChat"].isEnabled)
        app.buttons["sendChat"].tap()
        XCTAssertTrue(app.staticTexts["收到消息。"].waitForExistence(timeout: 6))
        app.terminate(); app.launch(); openChat(app)
        XCTAssertTrue(app.buttons["chatImageAttachment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["收到消息。"].exists)
        XCTAssertFalse(app.buttons["sendChat"].isEnabled)
    }
    func testOwnStaticAndGIFPacksAndAIStickerReply() {
        let app = launch()
        app.buttons["sendChat"].tap()
        XCTAssertTrue(app.staticTexts["收到消息。"].waitForExistence(timeout: 6))
        app.buttons["chatOpenStickers"].tap()
        XCTAssertTrue(app.buttons["chooseSticker-小白静态测试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chooseSticker-小白动态测试"].exists)
        XCTAssertFalse(app.buttons["chooseSticker-大肥鱼静态测试"].exists)
        app.buttons["chooseSticker-小白动态测试"].tap()
        XCTAssertTrue(app.buttons["chatStickerAttachment"].waitForExistence(timeout: 5))
        send("测试表情", in: app)
        XCTAssertTrue(app.staticTexts["已发送表情：小白动态测试"].waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "chatStickerAttachment").count, 2)
    }
    func testAppWriteRequiresConfirmationAndDeclineDoesNotClaimSuccess() {
        let app = launch()
        send("测试操作", in: app)
        let decline = app.buttons["declineChatAppAction"]
        XCTAssertTrue(decline.waitForExistence(timeout: 6))
        decline.tap()
        XCTAssertTrue(app.staticTexts["用户未确认，操作未执行。"].waitForExistence(timeout: 6))
        send("测试操作", in: app)
        let approve = app.buttons["approveChatAppAction"]
        XCTAssertTrue(approve.waitForExistence(timeout: 6)); approve.tap()
        XCTAssertTrue(app.staticTexts["展示图已更改。"].waitForExistence(timeout: 6))
    }
}
