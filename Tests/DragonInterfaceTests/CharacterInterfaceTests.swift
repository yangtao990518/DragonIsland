import XCTest
import Foundation
import CoreGraphics
import Darwin
import UIKit

final class CharacterInterfaceTests: XCTestCase {
    private func islandPixels(_ screenshot: XCUIScreenshot, scene: String? = nil) -> Int {
        guard let source = screenshot.image.cgImage else { return 0 }
        let scale = CGFloat(source.width) / 1206
        guard let crop = source.cropping(to: CGRect(x: 180*scale, y: 40*scale, width: 320*scale, height: 120*scale)) else { return 0 }
        var rgba = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                          bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(crop.width), height: CGFloat(crop.height)))
            return true
        }
        guard drawn else { return 0 }
        let selected = stride(from: 0, to: rgba.count, by: 4).filter {
            let r = Int(rgba[$0]), g = Int(rgba[$0+1]), b = Int(rgba[$0+2])
            if scene == "meadow" { return g > r + 8 && g > b + 3 && g < 100 && g > 25 }
            if scene == "night" { return b > r + 9 && b > g + 9 && b < 100 && b > 25 }
            return min(r,g,b)>100 && r>=g-3 && b>=r-5
        }
        if scene == nil, let first = selected.first, let last = selected.last {
            let height = (last / 4 / crop.width) - (first / 4 / crop.width) + 1
            // A collapsed island leaves the status-bar clock inside this wide ROI.
            // The clock is only ~38px high; never mistake it for a ~90px character.
            if CGFloat(height) < 50 * scale { return 0 }
        }
        return selected.count
    }
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

    func testGalleryDismissGesturesPreserveDoubleTapAndZoomedPan() {
        let app = start(["--preview-characters", "--appearance-light"])
        XCTAssertTrue(app.buttons["characterCard-xiaobai"].waitForExistence(timeout: 8))
        app.buttons["characterCard-xiaobai"].tap()
        XCTAssertTrue(app.buttons["artwork-chibi"].waitForExistence(timeout: 5))
        app.buttons["artwork-chibi"].tap()
        let image = app.scrollViews["artworkZoomScroll"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.doubleTap()
        let percentage = app.staticTexts["zoomPercentage"]
        expectation(for: NSPredicate(format: "label != %@", "100%"), evaluatedWith: percentage)
        waitForExpectations(timeout: 4)
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.1, thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        XCTAssertTrue(image.exists, "Dragging an enlarged image must not close the viewer")
        image.tap()
        XCTAssertTrue(app.buttons["artwork-standing"].waitForExistence(timeout: 5))
        app.buttons["artwork-standing"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.swipeDown()
        XCTAssertTrue(app.buttons["artwork-chibi"].waitForExistence(timeout: 5))
    }

    func testAutomaticIslandMotionContinuesWithoutButtons() throws {
        let app = start(["--preview-live-motion", "--record-motion-metadata", "--scene-meadow", "--appearance-dark"])
        sleep(3)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Live Activity must start for automatic motion validation")
        let beforeHome = XCTAttachment(screenshot: app.screenshot())
        beforeHome.name = "live-session-before-home"
        beforeHome.lifetime = .keepAlways
        add(beforeHome)
        guard app.buttons["结束本轮陪伴"].waitForExistence(timeout: 10) else {
            XCTFail("Live Activity did not remain active before leaving the app")
            return
        }
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for sample in 0..<3 {
            if sample > 0 { sleep(70) }
            for index in 0..<20 {
                let screenshot = springboard.screenshot()
                let frame = XCTAttachment(screenshot: screenshot)
                frame.name = "automatic-island-\(sample)-\(index)"
                frame.lifetime = .keepAlways
                add(frame)
                if index == 15 {
                    let pixels = islandPixels(screenshot)
                    XCTAssertGreaterThan(pixels, 200, "Actual system island must contain the portrait, not an empty island")
                    if pixels <= 200 { return }
                }
                usleep(130_000)
            }
        }
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
        sleep(2)
        let expanded = XCTAttachment(screenshot: springboard.screenshot())
        expanded.name = "system-island-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
        app.activate()
        XCTAssertTrue(app.buttons["结束本轮陪伴"].waitForExistence(timeout: 8) || app.staticTexts["小白正在陪你"].waitForExistence(timeout: 2))
    }

    func testMotionChoicesPersistAndOldTestButtonsAreGone() {
        let app = start(["--preview-tasks", "--appearance-light"])
        let walk = app.switches["walkMotionToggle"]
        XCTAssertTrue(walk.waitForExistence(timeout: 8))
        let before = walk.value as? String
        walk.tap()
        XCTAssertNotEqual(walk.value as? String, before)
        let selected = walk.value as? String
        app.terminate()
        app.launchArguments = ["--maiverse-capture", "--preview-tasks"]
        app.launch()
        XCTAssertTrue(app.switches["walkMotionToggle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.switches["walkMotionToggle"].value as? String, selected)
        XCTAssertFalse(app.buttons["test-walk"].exists)
    }

    func testIslandScenesUpdateActualActivityAndPersist() {
        let app = start(["--preview-about", "--preview-live-motion", "--scene-black", "--appearance-light"])
        let black = app.buttons["islandScene-black"]
        XCTAssertTrue(black.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@ AND enabled == true", "已选择"), evaluatedWith: black)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(black.value as? String, "已选择")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for scene in ["meadow", "night"] {
            let button = app.buttons["islandScene-\(scene)"]
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            button.tap()
            expectation(for: NSPredicate(format: "value == %@", "已选择"), evaluatedWith: button)
            waitForExpectations(timeout: 5)
            XCUIDevice.shared.press(.home)
            // ActivityKit.update does not acknowledge that SpringBoard has
            // committed a new presentation. Wait for the requested on-screen
            // landscape, not merely the app's selection or a fixed delay.
            var screenshot = springboard.screenshot()
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if islandPixels(screenshot, scene: scene) > 150 && islandPixels(screenshot) > 200 {
                    usleep(700_000)
                    screenshot = springboard.screenshot()
                    if islandPixels(screenshot, scene: scene) > 150 { break }
                }
                usleep(250_000)
                screenshot = springboard.screenshot()
            }
            XCTAssertGreaterThan(islandPixels(screenshot, scene: scene), 150, "Scene must actually reach the system island")
            XCTAssertGreaterThan(islandPixels(screenshot), 200, "The character must remain visible when changing scenery")
            let compact = XCTAttachment(screenshot: screenshot)
            compact.name = "scene-\(scene)-compact"; compact.lifetime = .keepAlways; add(compact)
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
            sleep(2)
            let expanded = XCTAttachment(screenshot: springboard.screenshot())
            expanded.name = "scene-\(scene)-expanded"; expanded.lifetime = .keepAlways; add(expanded)
            app.activate()
        }
        app.terminate()
        app.launchArguments = ["--maiverse-capture", "--preview-about"]
        app.launch()
        let night = app.buttons["islandScene-night"]
        XCTAssertTrue(night.waitForExistence(timeout: 8))
        XCTAssertEqual(night.value as? String, "已选择")
    }
}
