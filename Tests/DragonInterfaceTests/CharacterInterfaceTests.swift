import XCTest
import Foundation
import CoreGraphics
import Darwin
import UIKit

final class CharacterInterfaceTests: XCTestCase {
    private func portraitPixels(_ screenshot: XCUIScreenshot) -> Int {
        guard let source = screenshot.image.cgImage else { return 0 }
        let scale = CGFloat(source.width) / 1206
        guard let crop = source.cropping(to: CGRect(x: 300*scale, y: 40*scale, width: 135*scale, height: 110*scale)) else { return 0 }
        var rgba = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                          bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(crop.width), height: CGFloat(crop.height)))
            return true
        }
        guard drawn else { return 0 }
        return stride(from: 0, to: rgba.count, by: 4).filter {
            let r = Int(rgba[$0]), g = Int(rgba[$0+1]), b = Int(rgba[$0+2])
            return min(r,g,b)>100 && r>=g-3 && b>=r-5
        }.count
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
        let app = start(["--preview-live-motion", "--appearance-dark"])
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
                    let pixels = portraitPixels(screenshot)
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
}
