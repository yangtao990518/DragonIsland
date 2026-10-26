import XCTest

final class AlarmInterfaceTests: XCTestCase {
    private func launch(_ flags: [String] = ["--preview-alarms"]) -> XCUIApplication {
        addUIInterruptionMonitor(withDescription: "System alarm authorization") { alert in
            for label in ["Allow", "允许", "OK", "好"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--appearance-light"] + flags
        app.launch()
        return app
    }

    private func save(_ app: XCUIApplication) {
        app.buttons["saveCharacterAlarm"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(15)
        while app.buttons["saveCharacterAlarm"].exists && Date() < deadline {
            if let allow = springboard.alerts.buttons.allElementsBoundByIndex.first(where: {
                ["Allow", "允许", "OK", "好"].contains($0.label)
            }) { allow.tap() }
            else { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
        }
        XCTAssertFalse(app.buttons["saveCharacterAlarm"].exists, "Scheduling must succeed using the real system backend")
    }

    func testVoiceSelectionPreviewScheduleEditRestoreAndCancel() {
        let app = launch()
        XCTAssertTrue(app.buttons["newAlarm-xiaobai"].waitForExistence(timeout: 10))
        app.buttons["newAlarm-xiaobai"].tap()
        app.buttons["alarmPreset-5"].tap()
        app.buttons["chooseAlarmVoice"].tap()
        XCTAssertTrue(app.buttons["previewVoice-xiaobai-03"].waitForExistence(timeout: 5))
        app.buttons["previewVoice-xiaobai-03"].tap()
        XCTAssertTrue(app.buttons["停止试听"].waitForExistence(timeout: 3))
        app.buttons["selectVoice-xiaobai-03"].tap()
        XCTAssertTrue(app.buttons["saveCharacterAlarm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["俏皮报到"].exists)
        save(app)
        let cancel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cancelAlarm-")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 6))
        let initialID = cancel.identifier
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons[initialID].waitForExistence(timeout: 8), "Alarm survives app relaunch")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editAlarm-")).firstMatch.tap()
        XCTAssertTrue(app.buttons["saveCharacterAlarm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["俏皮报到"].exists)
        save(app)
        let afterEdit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cancelAlarm-")).firstMatch
        XCTAssertTrue(afterEdit.waitForExistence(timeout: 5))
        XCTAssertNotEqual(afterEdit.identifier, initialID, "Editing replaces the old system alarm")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "character-alarm-scheduled"
        shot.lifetime = .keepAlways
        add(shot)
        afterEdit.tap()
        XCTAssertTrue(app.staticTexts["还没有约好的时间"].waitForExistence(timeout: 5))
    }

    func testCompanionReminderIsCanceledWhenSessionEnds() {
        let app = launch([])
        let toggle = app.switches["companionVoiceToggle"]
        if !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        if toggle.value as? String != "1" { toggle.tap() }
        let start = app.buttons["startCompanion"]
        if !start.isHittable { app.swipeUp() }
        start.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            springboard.alerts.buttons["Allow"].tap()
        }
        let end = app.buttons["结束本轮陪伴"]
        XCTAssertTrue(end.waitForExistence(timeout: 15))
        app.tabBars.buttons["闹钟"].tap()
        XCTAssertTrue(app.staticTexts["随本轮陪伴结束而取消"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的世界"].tap()
        if !end.isHittable { app.swipeUp() }
        end.tap()
        app.tabBars.buttons["闹钟"].tap()
        XCTAssertTrue(app.staticTexts["还没有约好的时间"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的世界"].tap()
        if !toggle.isHittable { app.swipeUp() }
        if toggle.value as? String == "1" { toggle.tap() }
    }

    func testOneMinuteAlarmActuallyFiresAfterLeavingApp() {
        let app = launch()
        XCTAssertTrue(app.buttons["newAlarm-xiaobai"].waitForExistence(timeout: 10))
        app.buttons["newAlarm-xiaobai"].tap()
        app.buttons["alarmPreset-1"].tap()
        save(app)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let stop = springboard.buttons["知道啦"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 75), "The real scheduled AlarmKit alert must appear outside the app")
        let shot = XCTAttachment(screenshot: springboard.screenshot())
        shot.name = "one-minute-system-alarm-fired"
        shot.lifetime = .keepAlways
        add(shot)
        stop.tap()
        app.activate()
        XCTAssertTrue(app.staticTexts["还没有约好的时间"].waitForExistence(timeout: 8), "System stop reconciles saved alarms")
    }
}
