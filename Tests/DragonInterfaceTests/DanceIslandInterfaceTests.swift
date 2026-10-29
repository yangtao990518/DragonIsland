import XCTest
import UIKit

final class DanceIslandInterfaceTests: XCTestCase {
    private func visiblePortraitPixels(_ screenshot: XCUIScreenshot) -> Int {
        guard let source = screenshot.image.cgImage else { return 0 }
        let scale = CGFloat(source.width) / 1206
        guard let crop = source.cropping(to: CGRect(x: 180*scale, y: 40*scale, width: 320*scale, height: 120*scale)) else { return 0 }
        var rgba = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let c = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            c.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(crop.width), height: CGFloat(crop.height)))
            return true
        }
        guard drawn else { return 0 }
        let selected = stride(from: 0, to: rgba.count, by: 4).filter {
            let r=Int(rgba[$0]), g=Int(rgba[$0+1]), b=Int(rgba[$0+2])
            return min(r,g,b)>100 && r>=g-3 && b>=r-5
        }
        guard let first=selected.first, let last=selected.last,
              CGFloat(last/4/crop.width-first/4/crop.width+1)>50*scale else { return 0 }
        return selected.count
    }
    private func capture(_ springboard: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: springboard.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDancesOnActualSystemIsland() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--maiverse-capture", "--character-dafeiyu",
            "--preview-island-dances", "--scene-black", "--appearance-dark"]
        app.launch()
        XCTAssertTrue(app.buttons["结束本轮陪伴"].waitForExistence(timeout: 10),
                      "A real ActivityKit session must start before going home")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let readyDeadline = Date().addingTimeInterval(65)
        let recordingDeadline = Date().addingTimeInterval(105)
        capture(app, "dance-island-session-before-home")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Both original 12.096-second dances run in the existing 13-second
        // slots. Keep the app backgrounded throughout the compact recording.
        while visiblePortraitPixels(springboard.screenshot()) <= 200 && Date() < readyDeadline {
            Thread.sleep(forTimeInterval: 0.7)
        }
        XCTAssertGreaterThan(visiblePortraitPixels(springboard.screenshot()), 200,
                             "Wait for a real visible portrait; an empty camera pill is insufficient")
        var index = 0
        while Date() < recordingDeadline {
            capture(springboard, String(format: "dance-island-compact-%02d", index))
            XCTAssertGreaterThan(visiblePortraitPixels(springboard.screenshot()), 200,
                                 "The character must remain visible during both complete dance slots")
            index += 1
            Thread.sleep(forTimeInterval: 1.2)
        }
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.035))
            .press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 2)
        capture(springboard, "dance-island-expanded-existing-standing-art")
        let controls = springboard.buttons.matching(NSPredicate(format:
            "label CONTAINS %@", "招呼")).firstMatch
        if !controls.isHittable {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.035))
                .press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: 2)
            capture(springboard, "dance-island-expanded-retry")
        }
        // The screenshot and accessibility dump are retained even if system
        // control labels vary. Never treat an App mock preview as island proof.
        let dump = XCTAttachment(string: springboard.debugDescription)
        dump.name = "dance-island-expanded-system-accessibility"
        dump.lifetime = .keepAlways
        add(dump)
        XCTAssertTrue(controls.isHittable, "The real expanded island must expose its greeting control")
        app.activate()
        XCTAssertTrue(app.buttons["结束本轮陪伴"].waitForExistence(timeout: 8))
    }
}
