import XCTest

final class SurvivorInterfaceTests: XCTestCase {
    private func launch(upgrade: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu", "--chat-test-store", UUID().uuidString]
        if upgrade { app.launchArguments.append("--survivor-upgrade-preview") }
        app.launch()
        openGame(app)
        return app
    }
    private func show(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }
    private func openGame(_ app: XCUIApplication) {
        let entry = app.buttons["openSurvivorGame"]
        show(entry, in: app); entry.tap()
        XCTAssertTrue(app.staticTexts["选择出战角色"].waitForExistence(timeout: 10))
    }
    private func start(_ app: XCUIApplication) {
        let button = app.buttons["survivorStart"]
        show(button, in: app); button.tap()
        XCTAssertTrue(app.staticTexts["survivorTimer"].waitForExistence(timeout: 10))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func seconds(_ label: String) -> Int {
        let pieces = label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(pieces.count, 2)
        return pieces.count == 2 ? pieces[0] * 60 + pieces[1] : 0
    }
    func testNativeBattleClockMovementAndMenuPause() {
        let app = launch()
        capture(app, "survivor-character-selection")
        start(app)
        let timer = app.staticTexts["survivorTimer"]
        XCTAssertEqual(timer.value as? String, "运行中")
        expectation(for: NSPredicate(format: "label != %@", "20:00"), evaluatedWith: timer)
        waitForExpectations(timeout: 10)
        let joystick = app.descendants(matching: .any).matching(identifier: "survivorJoystick").firstMatch
        XCTAssertTrue(joystick.exists)
        joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        capture(app, "survivor-real-battle")
        app.buttons["survivorPause"].tap()
        XCTAssertTrue(app.buttons["survivorResume"].waitForExistence(timeout: 5))
        let frozen = timer.label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(timer.label, frozen)
        capture(app, "survivor-pause")
        app.buttons["survivorResume"].tap()
        expectation(for: NSPredicate(format: "label != %@", frozen), evaluatedWith: timer)
        waitForExpectations(timeout: 8)
    }
    func testUpgradeSelectionLearnsThunderAndResumesBattle() {
        let app = launch(upgrade: true)
        start(app)
        XCTAssertTrue(app.buttons["survivorUpgrade_thunder"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "survivorUpgrade_")).count, 3)
        capture(app, "survivor-three-upgrade-choices")
        app.buttons["survivorUpgrade_thunder"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "survivorThunderRank").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["survivorUpgrade_thunder"].exists)
        let timer = app.staticTexts["survivorTimer"]
        expectation(for: NSPredicate(format: "label != %@", "20:00"), evaluatedWith: timer)
        waitForExpectations(timeout: 8)
        capture(app, "survivor-learned-thunder")
    }
    func testSaveRelaunchContinueAndBackgroundPause() {
        let app = launch()
        start(app)
        let timer = app.staticTexts["survivorTimer"]
        expectation(for: NSPredicate(format: "label != %@", "20:00"), evaluatedWith: timer)
        waitForExpectations(timeout: 10)
        app.buttons["survivorPause"].tap()
        let saved = seconds(timer.label)
        app.buttons["survivorReturnLobby"].tap()
        app.buttons.matching(identifier: "survivorSaveExit").firstMatch.tap()
        XCTAssertTrue(app.buttons["survivorContinue"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); openGame(app)
        let resume = app.buttons["survivorContinue"]
        show(resume, in: app); resume.tap()
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(abs(seconds(timer.label) - saved), 3)
        let before = seconds(timer.label)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(timer.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(before - seconds(timer.label), 3)
        capture(app, "survivor-restored-run")
    }
}
