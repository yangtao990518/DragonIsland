import XCTest

final class SurvivorInterfaceTests: XCTestCase {
    private func launch(upgrade: Bool = false, stress: Bool = false, chain: Bool = false, scale: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu", "--chat-test-store", UUID().uuidString]
        if upgrade { app.launchArguments.append("--survivor-upgrade-preview") }
        if stress { app.launchArguments.append("--survivor-stress-preview") }
        if chain { app.launchArguments.append("--survivor-upgrade-chain-preview") }
        if scale { app.launchArguments.append("--survivor-scale-preview") }
        app.launch()
        openGame(app)
        return app
    }
    private func show(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            let viewport=app.windows.firstMatch.frame.insetBy(dx:12,dy:12)
            if element.exists && element.isHittable && viewport.contains(CGPoint(x:element.frame.midX,y:element.frame.midY)) { return }
            let scroll=app.scrollViews.containing(.button,identifier:element.identifier).firstMatch
            if scroll.exists {scroll.swipeUp()} else {app.swipeUp()}
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(CGPoint(x:element.frame.midX,y:element.frame.midY)))
    }
    private func openGame(_ app: XCUIApplication) {
        let entry = app.buttons["openSurvivorGame"]
        show(entry, in: app); entry.tap()
        XCTAssertTrue(app.staticTexts["选择出战角色"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:5))
        let portrait=expectation(for:NSPredicate { _,_ in app.windows.firstMatch.frame.width < app.windows.firstMatch.frame.height },evaluatedWith:app)
        wait(for:[portrait],timeout:8)
    }
    private func start(_ app: XCUIApplication) {
        let button = app.buttons["survivorStart"]
        show(button, in: app); button.tap()
        XCTAssertTrue(app.staticTexts["survivorTimer"].waitForExistence(timeout: 10))
        let landscape=expectation(for:NSPredicate { _,_ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height },evaluatedWith:app)
        wait(for:[landscape],timeout:10)
    }
    private func capture(_ app: XCUIApplication, _ name: String, landscape: Bool = true) {
        // iOS 26 app.screenshot() can crop a rotated fullScreenCover using the
        // original portrait application rectangle. Capture the actual display.
        let screenshot=XCUIScreen.main.screenshot()
        if landscape { XCTAssertGreaterThan(screenshot.image.size.width,screenshot.image.size.height) }
        else { XCTAssertLessThan(screenshot.image.size.width,screenshot.image.size.height) }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func seconds(_ label: String) -> Int {
        let pieces = label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(pieces.count, 2)
        return pieces.count == 2 ? pieces[0] * 60 + pieces[1] : 0
    }
    func testHD2DXiaobaiSelectionAndBattle() {
        let app=launch()
        let choice=app.buttons["survivorHero_xiaobai"];show(choice,in:app);choice.tap()
        start(app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","小白 · Lv.")).firstMatch.waitForExistence(timeout:10))
        capture(app,"hd2d-xiaobai-native-battle")
    }
    func testConfirmedSkeletonAndFlameNativeSmoke() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--maiverse-capture","--character-dafeiyu","--chat-test-store",UUID().uuidString,"--survivor-asset-smoke"]
        app.launch()
        let entry=app.buttons["openSurvivorGame"];show(entry,in:app);entry.tap()
        XCUIDevice.shared.orientation = .landscapeRight
        let landscape=expectation(for:NSPredicate {_,_ in app.windows.firstMatch.frame.width>app.windows.firstMatch.frame.height},evaluatedWith:app)
        wait(for:[landscape],timeout:10)
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"nativeAssetProofScene").firstMatch.waitForExistence(timeout:30))
        Thread.sleep(forTimeInterval:0.7);capture(app,"native-skeleton-flame-alpha-feet-start")
        Thread.sleep(forTimeInterval:4);capture(app,"native-skeleton-complete-duration-last-frame")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","4.097")).firstMatch.exists)
    }
    func testConfirmedBattleStartsWithMinimapAndNativeSkills() {
        let app=launch();start(app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "survivorPauseMap").firstMatch.exists)
        let timer=app.staticTexts["survivorTimer"]
        expectation(for:NSPredicate(format:"label != %@","20:00"),evaluatedWith:timer)
        waitForExpectations(timeout:15)
        app.buttons["survivorPause"].tap()
        XCTAssertTrue(app.buttons["survivorResume"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "survivorPauseMap").firstMatch.exists)
        capture(app,"confirmed-native-battle-minimap-and-icons")
    }
    func testNativeBattleClockMovementAndMenuPause() {
        let app = launch()
        capture(app, "survivor-character-selection", landscape: false)
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
    func testUpgradeSelectionStrengthensPixelSkillAndResumesBattle() {
        let app = launch(upgrade: true)
        start(app)
        XCTAssertTrue(app.buttons["survivorUpgrade_fx:fireball"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "survivorUpgrade_")).count, 3)
        capture(app, "survivor-three-upgrade-choices")
        app.buttons["survivorUpgrade_fx:fireball"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "survivorSkillRank_fireball").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["survivorUpgrade_fx:fireball"].exists)
        let timer = app.staticTexts["survivorTimer"]
        expectation(for: NSPredicate(format: "label != %@", "20:00"), evaluatedWith: timer)
        waitForExpectations(timeout: 8)
        capture(app, "survivor-pixelfx-upgraded")
    }
    func testCatalogSearchLivePreviewAndStarterSelection() {
        let app = launch()
        let entry = app.buttons["survivorSkillLibrary"]
        show(entry,in:app); entry.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:8))
        search.tap(); search.typeText("fireball\n")
        let card = app.buttons["pixelFXSkill_fireball"]
        XCTAssertTrue(card.waitForExistence(timeout:8)); card.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"pixelFXLivePreview").firstMatch.waitForExistence(timeout:5))
        capture(app,"pixelfx-native-live-preview", landscape: false)
        show(app.buttons["pixelFXChooseSkill"],in:app); app.buttons["pixelFXChooseSkill"].tap()
        XCTAssertTrue(app.buttons["survivorStart"].waitForExistence(timeout:8))
    }

    func testLobbyIsPortraitBattleIsLandscapeAndReturningRestoresPortrait() {
        let app = launch()
        capture(app, "portrait-prebattle-selection", landscape: false)
        start(app)
        let timer = app.staticTexts["survivorTimer"]
        expectation(for: NSPredicate(format: "label != %@", "20:00"), evaluatedWith: timer)
        waitForExpectations(timeout: 15)
        capture(app, "landscape-zoomed-out-battle")
        app.buttons["survivorPause"].tap()
        XCTAssertTrue(app.buttons["survivorResume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "survivorPauseMap").firstMatch.exists)
        app.buttons["survivorReturnLobby"].tap()
        app.buttons.matching(identifier: "survivorSaveExit").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["选择出战角色"].waitForExistence(timeout: 8))
        let portrait = expectation(for: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width < app.windows.firstMatch.frame.height
        }, evaluatedWith: app)
        wait(for: [portrait], timeout: 10)
        capture(app, "portrait-returned-selection", landscape: false)
    }

    func testFourConsecutiveUpgradesNeverReenterBattlePreparation() {
        let app=launch(upgrade:true,chain:true);start(app)
        let scene=app.descendants(matching:.any).matching(identifier:"survivorBattleScene").firstMatch
        let choice=app.buttons["survivorUpgrade_fx:fireball"]
        expectation(for:NSPredicate { _,_ in choice.isHittable && !app.descendants(matching:.any).matching(identifier:"survivorLoading").firstMatch.exists },evaluatedWith:app)
        waitForExpectations(timeout:15)
        XCTAssertEqual(scene.value as? String,"资源准备次数：1")
        for level in 2...5 {
            choice.tap()
            if level<5 {XCTAssertTrue(app.staticTexts["Lv.\(level) → \(level+1)"].waitForExistence(timeout:5))}
            XCTAssertEqual(scene.value as? String,"资源准备次数：1")
            XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"survivorLoading").firstMatch.exists)
        }
        let timer=app.staticTexts["survivorTimer"]
        expectation(for:NSPredicate(format:"label != %@","20:00"),evaluatedWith:timer)
        waitForExpectations(timeout:10)
        XCTAssertEqual(timer.value as? String,"运行中")
        XCTAssertEqual(scene.value as? String,"资源准备次数：1")
        capture(app,"four-upgrades-without-resource-reload")
    }

    func testSmallCharacterAndMixedMonstersInRealBattle() {
        let app=launch(scale:true);start(app)
        let timer=app.staticTexts["survivorTimer"]
        expectation(for:NSPredicate(format:"label != %@","20:00"),evaluatedWith:timer)
        waitForExpectations(timeout:15)
        capture(app,"small-scale-hero-normal-elite-boss-real-battle")
        app.buttons["survivorPause"].tap()
        XCTAssertTrue(app.buttons["survivorResume"].waitForExistence(timeout:5))
        let map=app.descendants(matching:.any).matching(identifier:"survivorPauseMap").firstMatch
        XCTAssertTrue(map.exists)
        capture(app,"small-scale-matching-camera-map")
    }

    func testSixMaxRankSkillsAndCrowdKeepSimulationMoving() {
        let app=launch(stress:true)
        start(app)
        let timer=app.staticTexts["survivorTimer"]
        XCTAssertTrue(timer.waitForExistence(timeout:15))
        // Higher durability changes kill/pickup timing. A legitimate upgrade
        // pauses simulation; resolve it rather than tapping through its modal.
        func resolveUpgrade() -> Bool {
            let choice = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","survivorUpgrade_")).firstMatch
            guard choice.exists else { return false }
            choice.tap()
            XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"survivorLoading").firstMatch.exists)
            return true
        }
        let startSeconds = seconds(timer.label), deadline = Date().addingTimeInterval(60)
        while startSeconds - seconds(timer.label) < 8 && Date() < deadline {
            if !resolveUpgrade() { Thread.sleep(forTimeInterval:0.2) }
        }
        XCTAssertGreaterThanOrEqual(startSeconds - seconds(timer.label), 8, "Eight seconds of simulation, excluding upgrade pauses")
        _ = resolveUpgrade()
        capture(app,"survivor-six-skill-crowd")
        let resume = app.buttons["survivorResume"]
        for _ in 0..<8 {
            if resolveUpgrade() { continue }
            app.buttons["survivorPause"].tap()
            if resume.waitForExistence(timeout:2) { break }
        }
        XCTAssertTrue(resume.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","已装备6项技能")).firstMatch.exists)
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
