import Foundation

/// World units stay unchanged: camera zoom changes the size of everything on
/// screen together, including hit areas, projectiles and the map's view box.
enum SurvivorViewport {
    // 100-world-unit hero -> 40pt, ordinary 72-unit enemy -> 28.8pt.
    // Half the on-screen size of the previous 1.25 camera.
    static let cameraScale = 2.5

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

    static func contains(_ point: SurvivorVector, player: SurvivorVector, width: Double, height: Double) -> Bool {
        let visible = size(width: width, height: height)
        let origin = center(player: player, width: width, height: height)
        return abs(point.x - origin.x) <= visible.x / 2 && abs(point.y - origin.y) <= visible.y / 2
    }

    static func spawnPoint(player: SurvivorVector, width: Double, height: Double,
                           angle: Double, padding: Double) -> SurvivorVector {
        let visible = size(width: width, height: height)
        let origin = center(player: player, width: width, height: height)
        func edge(_ direction: SurvivorVector) -> SurvivorVector {
            let x = abs(direction.x) > 0.000001 ? (visible.x / 2 + padding) / abs(direction.x) : Double.infinity
            let y = abs(direction.y) > 0.000001 ? (visible.y / 2 + padding) / abs(direction.y) : Double.infinity
            return SurvivorGrassland.clamp(origin + direction * min(x, y))
        }
        let proposed = edge(.init(x: cos(angle), y: sin(angle)))
        if !contains(proposed, player: player, width: width, height: height) { return proposed }
        // At an outer wall, spawn beyond the inward screen edge, not inside
        // the visible rectangle after clamping an out-of-world candidate.
        let inward = origin.length > 0.001 ? origin.normalized * -1 : .init(x: 1, y: 0)
        return edge(inward)
    }

    static func floorTileCount(span: Double, side: Double) -> Int {
        max(3, Int(ceil(span / side)) + 3)
    }

    static func recycleDistance(player: SurvivorVector, width: Double, height: Double) -> Double {
        let visible = size(width: width, height: height)
        let origin = center(player: player, width: width, height: height)
        let x = abs(player.x - origin.x) + visible.x / 2
        let y = abs(player.y - origin.y) + visible.y / 2
        return max(950, hypot(x, y) + 400)
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
