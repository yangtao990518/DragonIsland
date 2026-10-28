import Foundation

struct FullVideoAction: Decodable, Sendable {
    let id: String
    let action: String
    let characterID: String
    let title: String
    let durationMs: Double
    let frameCount: Int
    let cellSize: [Int]
    let grid: [Int]
    let atlases: [String]
    let frameStartMs: [Double]
    let frameDurationsMs: [Double]

    /// Select original PTS intervals; never infer pose index from average FPS.
    func frameIndex(elapsed: TimeInterval) -> Int {
        guard !frameStartMs.isEmpty else { return 0 }
        let ms = max(0, elapsed * 1000)
        var low = 0, high = frameStartMs.count
        while low < high {
            let middle = (low + high) / 2
            if frameStartMs[middle] <= ms { low = middle + 1 } else { high = middle }
        }
        return max(0, min(frameCount - 1, low - 1))
    }
    static func load(bundle: Bundle = .main) -> [FullVideoAction] {
        guard let url = bundle.url(forResource: "VideoActions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let clips = try? JSONDecoder().decode([FullVideoAction].self, from: data) else { return [] }
        return clips.filter { $0.frameCount > 0 && $0.frameStartMs.count == $0.frameCount
            && $0.frameDurationsMs.count == $0.frameCount && $0.cellSize.count == 2 && $0.grid.count == 2
            && $0.cellSize.allSatisfy { $0 > 0 } && $0.grid.allSatisfy { $0 > 0 } }
    }
}
