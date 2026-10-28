import Foundation

struct MotionSettings: Codable, Equatable {
    var automatic = true
    var walk = true
    var roll = true
    var mask: Int { (walk ? 1 : 0) | (roll ? 2 : 0) }
    func plan(seed: Int) -> Int? { automatic ? mask * 2 + abs(seed % 2) : nil }
    static func load() -> MotionSettings {
        guard let data = UserDefaults.standard.data(forKey: "motionSettings"),
              let value = try? JSONDecoder().decode(MotionSettings.self, from: data) else { return MotionSettings() }
        return value
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "motionSettings") }
}

struct MotionFrame: Decodable {
    let asset: String
    let x: Int
    let action: String
    var width: Int? = nil
    var height: Int? = nil
}

struct MotionTimeline: Decodable {
    struct Leg: Decodable { let action: String; let direction: String; let start: Int; let duration: Int }
    struct Plan: Decodable { let id: Int; let mask: Int; let slots: [String]; let frames: [MotionFrame]; let legs: [Leg]? }
    let fps: Int
    let period: Int
    let plans: [Plan]
    let previews: [String: [MotionFrame]]?
    let appPreviews: [String: [MotionFrame]]?
    let previewFPS: Int?
    let durations: [String: [Int]]?
    let stagePixels: [Int]?
    let travelPixels: Int?
    let scenes: [String]?
    static let shared: MotionTimeline? = {
        guard let url = Bundle.main.url(forResource: "MotionTimeline", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MotionTimeline.self, from: data)
    }()
    private static let characterTimelines: [String: MotionTimeline] = {
        var result: [String: MotionTimeline] = [:]
        for character in CharacterCatalog.load() {
            guard let profile = character.motionProfile,
                  let url = Bundle.main.url(forResource: profile.timelineResource, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let value = try? JSONDecoder().decode(MotionTimeline.self, from: data) else { continue }
            result[character.id] = value
        }
        return result
    }()
    static func timeline(for character: CompanionCharacter) -> MotionTimeline? {
        characterTimelines[character.id] ?? (character.id == "xiaobai" ? shared : nil)
    }
    func frame(plan: Int, elapsed: TimeInterval) -> MotionFrame? {
        guard let value = plans.first(where: { $0.id == plan }), !value.frames.isEmpty else { return nil }
        return value.frames[max(0, Int(elapsed * Double(fps))) % value.frames.count]
    }
    func preview(action: String, elapsed: TimeInterval) -> MotionFrame? {
        if let frames = appPreviews?[action], !frames.isEmpty {
            return frames[max(0, Int(elapsed * Double(previewFPS ?? fps))) % frames.count]
        }
        guard let frames = previews?[action], !frames.isEmpty else { return nil }
        return frames[max(0, Int(elapsed * Double(fps))) % frames.count]
    }
}


