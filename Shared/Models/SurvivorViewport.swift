import Foundation

/// World units stay unchanged: camera zoom changes the size of everything on
/// screen together, including hit areas, projectiles and the map's view box.
enum SurvivorViewport {
    static let cameraScale = 1.25

    static func size(width: Double, height: Double) -> SurvivorVector {
        .init(x: width * cameraScale, y: height * cameraScale)
    }

    static func center(player: SurvivorVector, width: Double, height: Double) -> SurvivorVector {
        let visible = size(width: width, height: height)
        let half = SurvivorGrassland.halfSide
        let xLimit = max(0, half - visible.x / 2)
        let yLimit = max(0, half - visible.y / 2)
        return .init(x: max(-xLimit, min(xLimit, player.x)),
                     y: max(-yLimit, min(yLimit, player.y + 55)))
    }
}

/// North-up square map. Zoom follows the player and clamps at world edges.
struct SurvivorMapProjection {
    let side: Double
    let center: SurvivorVector

    init(player: SurvivorVector, zoom: Double) {
        let zoom = zoom.isFinite ? min(4, max(1, zoom)) : 1
        side = SurvivorGrassland.halfSide * 2 / zoom
        let limit = max(0, SurvivorGrassland.halfSide - side / 2)
        center = .init(x: max(-limit, min(limit, player.x)),
                       y: max(-limit, min(limit, player.y)))
    }

    func normalized(_ point: SurvivorVector) -> SurvivorVector {
        .init(x: 0.5 + (point.x - center.x) / side,
              y: 0.5 - (point.y - center.y) / side)
    }
}

/// Samples render callbacks rather than the configured 60 FPS target. Pauses
/// reset the sampling window without counting background time as a hitch.
struct SurvivorRenderStatistics {
    private(set) var framesPerSecond = 0
    private(set) var slowFrames = 0
    private(set) var longestFrameMS = 0.0
    private var previous: Double?
    private var windowDuration = 0.0
    private var windowFrames = 0

    mutating func resumeSampling() {
        previous = nil; windowDuration = 0; windowFrames = 0
    }

    @discardableResult mutating func record(at timestamp: Double) -> Bool {
        guard timestamp.isFinite else { return false }
        guard let last = previous else { previous = timestamp; return false }
        guard timestamp > last else { return false }
        previous = timestamp
        let delta = timestamp - last
        longestFrameMS = max(longestFrameMS, delta * 1000)
        if delta > 1.0 / 45 { slowFrames += 1 }
        windowDuration += delta; windowFrames += 1
        guard windowDuration >= 1 - 0.000001 else { return false }
        framesPerSecond = Int((Double(windowFrames) / windowDuration).rounded())
        windowDuration = 0; windowFrames = 0
        return true
    }
}
