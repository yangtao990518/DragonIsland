import Foundation
import XCTest
@testable import DragonDomain

final class FullVideoActionTests: XCTestCase {
    func testOriginalPTSIntervalsAndFinalPictureHold() throws {
        let data = Data(#"{"id":"dance","action":"dance1","characterID":"dafeiyu","title":"舞蹈1","durationMs":180,"frameCount":4,"cellSize":[60,90],"grid":[2,2],"atlases":["page"],"frameStartMs":[0,16.666667,50,66.666667],"frameDurationsMs":[16.666667,33.333333,16.666667,113.333333]}"#.utf8)
        let clip = try JSONDecoder().decode(FullVideoAction.self, from: data)
        XCTAssertEqual(clip.frameIndex(elapsed: -1), 0)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.04), 1) // The longer original interval is retained.
        XCTAssertEqual(clip.frameIndex(elapsed: 0.05), 2)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.179), 3)
        XCTAssertEqual(clip.frameIndex(elapsed: 10), 3) // Complete playback holds, never silently loops.
    }
    func testCompactTimelineResolvesFrameTableWithoutExpandingEveryPlan() throws {
        let data = Data(#"{"fps":1,"period":120,"frameTable":[{"asset":"first","x":0,"action":"dance1","videoAction":"dance1","sourceFrame":0},{"asset":"last","x":0,"action":"dance1","videoAction":"dance1","sourceFrame":719}],"plans":[{"id":32,"mask":16,"slots":[],"frames":[],"frameIndices":[0,1]}]}"#.utf8)
        let timeline = try JSONDecoder().decode(MotionTimeline.self, from: data)
        XCTAssertEqual(timeline.frame(plan: 32, elapsed: 0)?.sourceFrame, 0)
        XCTAssertEqual(timeline.frame(plan: 32, elapsed: 1)?.sourceFrame, 719)
        XCTAssertEqual(timeline.frame(plan: 32, elapsed: 2)?.sourceFrame, 0)
        XCTAssertNil(timeline.frame(plan: 1, elapsed: 0))
    }
}
