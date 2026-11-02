import XCTest
@testable import DragonDomain

final class SurvivorViewportTests: XCTestCase {
    func testZoomShrinksEverythingWithoutChangingWorldCoordinates() {
        let viewport = SurvivorViewport.size(width: 844, height: 390)
        XCTAssertEqual(viewport.x, 1055)
        XCTAssertEqual(viewport.y, 487.5)
        XCTAssertEqual(100 / SurvivorViewport.cameraScale, 80)
    }

    func testCameraViewRemainsInsideWorldAtEveryCorner() {
        let visible = SurvivorViewport.size(width: 844, height: 390)
        for x in [-6400.0, 0, 6400] {
            for y in [-6400.0, 0, 6400] {
                let center = SurvivorViewport.center(player: .init(x: x, y: y), width: 844, height: 390)
                XCTAssertLessThanOrEqual(abs(center.x) + visible.x / 2, 6400)
                XCTAssertLessThanOrEqual(abs(center.y) + visible.y / 2, 6400)
            }
        }
    }

    func testFullMapUsesActualWorldExtentsAndNorthIsUp() {
        let map = SurvivorMapProjection(player: .init(x: 6000, y: 6000), zoom: 1)
        XCTAssertEqual(map.normalized(.init(x: -6400, y: 6400)), .zero)
        XCTAssertEqual(map.normalized(.init(x: 6400, y: -6400)), .init(x: 1, y: 1))
        XCTAssertEqual(map.normalized(.zero), .init(x: 0.5, y: 0.5))
    }

    func testZoomFollowsPlayerAndStopsAtStageEdge() {
        let map = SurvivorMapProjection(player: .init(x: 200, y: 300), zoom: 4)
        XCTAssertEqual(map.normalized(.init(x: 200, y: 300)), .init(x: 0.5, y: 0.5))
        let edge = SurvivorMapProjection(player: .init(x: 6400, y: -6400), zoom: 4)
        XCTAssertEqual(edge.normalized(.init(x: 6400, y: -6400)), .init(x: 1, y: 1))
    }

    func testRenderRateReportsMeasuredThirtyAndSixtyRatherThanTarget() {
        for fps in [30, 60] {
            var statistics = SurvivorRenderStatistics()
            for i in 0...fps { statistics.record(at: Double(i) / Double(fps)) }
            XCTAssertEqual(statistics.framesPerSecond, fps)
            XCTAssertEqual(statistics.slowFrames, fps == 30 ? 30 : 0)
        }
    }

    func testPauseDoesNotPolluteRateOrHitchCounts() {
        var statistics = SurvivorRenderStatistics()
        statistics.record(at: 0); statistics.record(at: 0.05)
        XCTAssertEqual(statistics.slowFrames, 1)
        statistics.resumeSampling()
        statistics.record(at: 100)
        statistics.record(at: 100 + 1.0 / 60)
        XCTAssertEqual(statistics.slowFrames, 1)
        XCTAssertEqual(statistics.longestFrameMS, 50, accuracy: 0.001)
    }
}
