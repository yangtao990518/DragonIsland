import XCTest

final class AIChatInterfaceTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--preview-chat", "--appearance-light", "--chat-test-store", UUID().uuidString]
        app.launch()
        return app
    }
    private func configure(_ app: XCUIApplication, _ name: String) {
        app.buttons["chatPreferences"].tap()
        app.buttons["\(name) · AI 与人格"].tap()
        XCTAssertTrue(app.buttons["saveAISettings"].waitForExistence(timeout: 5))
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func testPerCharacterThinkingSettingPersistsAndDoesNotChangeOtherRole() {
        let app = launch()
        configure(app, "小白")
        let toggle = app.switches["characterAIThinking"]
        reveal(toggle, app)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        app.buttons["saveAISettings"].tap()
        app.terminate(); app.launch()
        configure(app, "小白")
        reveal(toggle, app)
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["保存"].tap()
        configure(app, "大肥鱼")
        reveal(toggle, app)
        XCTAssertEqual(toggle.value as? String, "0")
    }
    func testKeychainCredentialCanBeSavedReadAfterRelaunchAndRemoved() {
        let app = launch()
        configure(app, "小白")
        let field = app.secureTextFields["deepseekKey"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sk-ui-test-dummy-only")
        app.buttons["saveDeepseekKey"].tap()
        XCTAssertTrue(app.staticTexts["密钥已保存在本机。"].waitForExistence(timeout: 5))
        app.buttons["saveAISettings"].tap()
        app.terminate(); app.launch()
        configure(app, "大肥鱼")
        XCTAssertTrue(app.buttons["移除密钥"].waitForExistence(timeout: 5))
        app.buttons["移除密钥"].tap()
        XCTAssertTrue(app.staticTexts["密钥已移除。"].waitForExistence(timeout: 5))
    }
    func testBackupEntryExplainsLocalStorageAndExportIsAvailable() {
        let app = launch()
        app.buttons["chatPreferences"].tap(); app.buttons["本地备份"].tap()
        XCTAssertTrue(app.buttons["exportChatBackup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exportChatBackup"].isEnabled)
        XCTAssertTrue(app.buttons["importChatBackup"].isEnabled)
    }
    func testRealProviderWithoutKeyShowsConfigurationErrorAndKeepsMessage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Deliberately omit the capture/mock flag. A fresh keychain namespace has no real key.
        app.launchArguments = ["--preview-chat", "--appearance-light", "--chat-test-store", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["startDirectChat"].waitForExistence(timeout: 8))
        app.buttons["startDirectChat"].tap()
        XCTAssertTrue(app.buttons["chatSelect-xiaobai"].waitForExistence(timeout: 5))
        app.buttons["chatSelect-xiaobai"].tap(); app.buttons["saveChat"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "chatInput").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Hello without key"); app.buttons["sendChat"].tap()
        XCTAssertTrue(app.alerts["聊天"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["请先在角色详情的「AI 与人格」中配置 DeepSeek 密钥。"].exists)
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.staticTexts["Hello without key"].exists)
        XCTAssertFalse(app.staticTexts["聊天功能测试中"].exists)
    }
}
