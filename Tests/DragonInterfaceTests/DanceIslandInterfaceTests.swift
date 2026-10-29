import XCTest
import UIKit

final class DanceIslandInterfaceTests: XCTestCase {
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
        capture(app, "dance-island-session-before-home")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Both original 12.096-second dances run in the existing 13-second
        // slots. Keep the app backgrounded throughout the compact recording.
        let deadline = Date().addingTimeInterval(39)
        var index = 0
        while Date() < deadline {
            capture(springboard, String(format: "dance-island-compact-%02d", index))
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
