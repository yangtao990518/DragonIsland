import Foundation

/// Original video timestamps, including gaps and the final held frame.
struct SurvivorMedia: Decodable {
    let clips: [Clip]
    struct Page: Decodable { let file: String }
    struct Frame: Decodable {
        let cell: Int
        let startMS: Double
        let durationMS: Double
        enum CodingKeys: String, CodingKey {
            case cell, startMS = "start_ms", durationMS = "duration_ms"
        }
    }
    struct Clip: Decodable {
        let id: String
        let cellSize: [Int]
        let grid: [Int]
        let pivot: [Double]
        let durationMS: Double
        let pages: [Page]
        let frames: [Frame]
        enum CodingKeys: String, CodingKey {
            case id, grid, pivot, pages, frames
            case cellSize = "cell_size", durationMS = "duration_ms"
        }
        func frame(at seconds: Double, looping: Bool) -> Frame? {
            guard seconds.isFinite, !frames.isEmpty, durationMS > 0 else { return nil }
            let raw = max(0, seconds * 1000)
            let time = looping ? raw.truncatingRemainder(dividingBy: durationMS) : min(raw, durationMS)
            var low = 0, high = frames.count
            while low < high {
                let middle = (low + high) / 2
                if frames[middle].startMS <= time { low = middle + 1 } else { high = middle }
            }
            return frames[max(0, low - 1)]
        }
    }
    func validate() throws {
        guard !clips.isEmpty, Set(clips.map(\.id)).count == clips.count else { throw SurvivorRuleError.invalidConfiguration }
        for clip in clips {
            guard clip.cellSize.count == 2, clip.cellSize.allSatisfy({ $0 > 0 }),
                  clip.grid.count == 2, clip.grid.allSatisfy({ $0 > 0 }),
                  clip.pivot.count == 2, clip.pivot.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  clip.durationMS.isFinite, clip.durationMS > 0, clip.durationMS <= 20_000,
                  !clip.pages.isEmpty, !clip.frames.isEmpty else { throw SurvivorRuleError.invalidConfiguration }
            var end = 0.0
            for frame in clip.frames {
                guard frame.startMS.isFinite, frame.durationMS.isFinite, frame.durationMS > 0,
                      abs(frame.startMS - end) < 0.01, frame.cell >= 0,
                      frame.cell < clip.pages.count * clip.grid[0] * clip.grid[1] else { throw SurvivorRuleError.invalidConfiguration }
                end = frame.startMS + frame.durationMS
            }
            guard abs(end - clip.durationMS) < 0.01 else { throw SurvivorRuleError.invalidConfiguration }
            for page in clip.pages {
                guard !page.file.hasPrefix("/"), !page.file.contains(".."), page.file.hasSuffix(".png") else {
                    throw SurvivorRuleError.invalidConfiguration
                }
            }
        }
    }
}
