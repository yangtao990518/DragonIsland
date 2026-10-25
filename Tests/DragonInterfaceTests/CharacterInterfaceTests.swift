import XCTest
import Foundation
import CoreGraphics
import Darwin

final class CharacterInterfaceTests: XCTestCase {
    private func start(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture"] + arguments
        app.launch()
        return app
    }

    func testChibiGallerySupportsPinchResetAndBackground() {
        let app = start(["--preview-characters", "--appearance-light"])
        let card = app.buttons["characterCard-xiaobai"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let chibi = app.buttons["artwork-chibi"]
        XCTAssertTrue(chibi.waitForExistence(timeout: 5))
        chibi.tap()
        let image = app.scrollViews["artworkZoomScroll"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.pinch(withScale: 2, velocity: 1)
        let percentage = app.staticTexts["zoomPercentage"]
        XCTAssertTrue(percentage.waitForExistence(timeout: 3))
        XCTAssertNotEqual(percentage.label, "100%")
        app.buttons["resetArtworkZoom"].tap()
        expectation(for: NSPredicate(format: "label == %@", "100%"), evaluatedWith: percentage)
        waitForExpectations(timeout: 4)
        app.buttons["galleryBackgroundToggle"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "chibi-fullscreen-after-zoom"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["closeArtwork"].tap()
        XCTAssertTrue(app.buttons["artwork-standing"].waitForExistence(timeout: 4))
    }

    func testStandingArtOpensSeparately() {
        let app = start(["--preview-characters", "--appearance-dark"])
        XCTAssertTrue(app.buttons["characterCard-xiaobai"].waitForExistence(timeout: 8))
        app.buttons["characterCard-xiaobai"].tap()
        XCTAssertTrue(app.buttons["artwork-standing"].waitForExistence(timeout: 5))
        app.buttons["artwork-standing"].tap()
        XCTAssertTrue(app.scrollViews["artworkZoomScroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["小白 · 展开立绘"].exists)
    }

    func testAppearanceChoiceSurvivesRelaunch() {
        let app = start(["--appearance-light"])
        let toggle = app.buttons["appearanceToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "浅色")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "深色")
        app.terminate()
        app.launchArguments = ["--maiverse-capture"]
        app.launch()
        XCTAssertTrue(app.buttons["appearanceToggle"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["appearanceToggle"].firstMatch.value as? String, "深色")
    }

    func testCaptureSystemIslandMotionSample() throws {
        let app = start(["--preview-live-motion", "--appearance-dark"])
        sleep(3)
        if app.alerts.firstMatch.exists {
            let failure = XCTAttachment(screenshot: app.screenshot())
            failure.name = "live-activity-unavailable"
            failure.lifetime = .keepAlways
            add(failure)
            throw XCTSkip("Live Activity could not start in this simulator; physical-device validation remains required")
        }
        let sample = app.buttons["test-walk"]
        for _ in 0..<4 { if sample.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        XCUIDevice.shared.press(.home)
        sleep(4)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for index in 0..<12 {
            let frame = XCTAttachment(screenshot: springboard.screenshot())
            frame.name = "system-island-motion-\(index)"
            frame.lifetime = .keepAlways
            add(frame)
            usleep(150_000)
        }
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
        sleep(2)
        let expanded = XCTAttachment(screenshot: springboard.screenshot())
        expanded.name = "system-island-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
        app.activate()
        let roll = app.buttons["test-roll"]
        for _ in 0..<4 { if roll.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(roll.waitForExistence(timeout: 5))
        roll.tap()
        XCUIDevice.shared.press(.home)
        sleep(4)
        for index in 0..<12 {
            let frame = XCTAttachment(screenshot: springboard.screenshot())
            frame.name = "system-island-roll-\(index)"
            frame.lifetime = .keepAlways
            add(frame)
            usleep(150_000)
        }
    }
}
