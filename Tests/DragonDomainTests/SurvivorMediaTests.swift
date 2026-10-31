import Foundation
import XCTest
@testable import DragonDomain

final class SurvivorMediaTests: XCTestCase {
    private func fixture() throws -> SurvivorMedia {
        let json = #"{"clips":[{"id":"test","cell_size":[30,40],"grid":[2,2],"pivot":[0.5,0.1],"duration_ms":100,"pages":[{"file":"test/a.png"}],"frames":[{"cell":0,"start_ms":0,"duration_ms":16.667},{"cell":1,"start_ms":16.667,"duration_ms":33.333},{"cell":2,"start_ms":50,"duration_ms":50}]}]}"#
        return try JSONDecoder().decode(SurvivorMedia.self, from: Data(json.utf8))
    }
    func testVariableFrameIntervalsAndFinalHoldAreSelectedByTimestamp() throws {
        let media = try fixture()
        try media.validate()
        let clip = try XCTUnwrap(media.clips.first)
        XCTAssertEqual(clip.frame(at: 0, looping: false)?.cell, 0)
        XCTAssertEqual(clip.frame(at: 0.02, looping: false)?.cell, 1)
        XCTAssertEqual(clip.frame(at: 0.049, looping: false)?.cell, 1)
        XCTAssertEqual(clip.frame(at: 0.099, looping: false)?.cell, 2)
        XCTAssertEqual(clip.frame(at: 5, looping: false)?.cell, 2)
        XCTAssertEqual(clip.frame(at: 0.1, looping: true)?.cell, 0)
        XCTAssertNil(clip.frame(at: .nan, looping: true))
    }
    func testBrokenTimelineAndEscapingResourcePathAreRejected() throws {
        let encoder = #"{"clips":[{"id":"bad","cell_size":[1,1],"grid":[1,1],"pivot":[0.5,0.5],"duration_ms":100,"pages":[{"file":"../a.png"}],"frames":[{"cell":0,"start_ms":0,"duration_ms":100}]}]}"#
        let invalidPath = try JSONDecoder().decode(SurvivorMedia.self, from: Data(encoder.utf8))
        XCTAssertThrowsError(try invalidPath.validate())
        let brokenTime = encoder.replacingOccurrences(of: "../a.png", with: "a.png")
            .replacingOccurrences(of: "\"duration_ms\":100}]", with: "\"duration_ms\":50}]")
        let invalidTime = try JSONDecoder().decode(SurvivorMedia.self, from: Data(brokenTime.utf8))
        XCTAssertThrowsError(try invalidTime.validate())
    }
}
