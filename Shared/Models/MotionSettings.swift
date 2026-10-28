import Foundation

struct MotionSettings: Codable, Equatable {
    var automatic = true
    var walk = true
    var roll = true
    var ride = true
    var petWalk = true
    var dance1 = false
    var dance2 = false
    var mask: Int { (walk ? 1 : 0) | (roll ? 2 : 0) | (ride ? 4 : 0) | (petWalk ? 8 : 0) | (dance1 ? 16 : 0) | (dance2 ? 32 : 0) }
    func mask(for character: CompanionCharacter) -> Int {
        let actions = Set((character.motionProfile?.dailyActions ?? []).map(\.id))
        return (walk ? 1 : 0) | (roll ? 2 : 0)
            | (ride && actions.contains("ride") ? 4 : 0)
            | (petWalk && actions.contains("pet_walk") ? 8 : 0)
            | (dance1 && actions.contains("dance1") ? 16 : 0)
            | (dance2 && actions.contains("dance2") ? 32 : 0)
    }
    func plan(seed: Int) -> Int? { automatic ? mask * 2 + abs(seed % 2) : nil }
    func plan(seed: Int, character: CompanionCharacter) -> Int? {
        automatic ? mask(for: character) * 2 + abs(seed % 2) : nil
    }
    static func supports(plan: Int, for character: CompanionCharacter) -> Bool {
        guard character.motionProfile != nil else { return false }
        let maximum = MotionSettings(dance1: true, dance2: true).mask(for: character) * 2 + 1
        return (0...maximum).contains(plan)
    }
    init(automatic: Bool = true, walk: Bool = true, roll: Bool = true,
         ride: Bool = true, petWalk: Bool = true, dance1: Bool = false, dance2: Bool = false) {
        self.automatic = automatic; self.walk = walk; self.roll = roll
        self.ride = ride; self.petWalk = petWalk
        self.dance1 = dance1; self.dance2 = dance2
    }
    private enum CodingKeys: String, CodingKey { case automatic, walk, roll, ride, petWalk, dance1, dance2 }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? true
        walk = try values.decodeIfPresent(Bool.self, forKey: .walk) ?? true
        roll = try values.decodeIfPresent(Bool.self, forKey: .roll) ?? true
        // Old releases grouped all travelling activities under walk.
        ride = try values.decodeIfPresent(Bool.self, forKey: .ride) ?? walk
        petWalk = try values.decodeIfPresent(Bool.self, forKey: .petWalk) ?? walk
        dance1 = try values.decodeIfPresent(Bool.self, forKey: .dance1) ?? false
        dance2 = try values.decodeIfPresent(Bool.self, forKey: .dance2) ?? false
    }
    static func load() -> MotionSettings {
        guard let data = UserDefaults.standard.data(forKey: "motionSettings"),
              let value = try? JSONDecoder().decode(MotionSettings.self, from: data) else { return MotionSettings() }
        return value
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "motionSettings") }
    static func loadCharacters(from defaults: UserDefaults = .standard) -> [String: MotionSettings] {
        guard let data = defaults.data(forKey: "characterMotionSettings"),
              let values = try? JSONDecoder().decode([String: MotionSettings].self, from: data) else { return [:] }
        return values
    }
    static func saveCharacters(_ values: [String: MotionSettings], to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(values), forKey: "characterMotionSettings")
    }
}

struct MotionFrame: Decodable {
    let asset: String
    let x: Int
    let action: String
    var width: Int? = nil
    var height: Int? = nil
    var videoAction: String? = nil
    var sourceFrame: Int? = nil
}

struct MotionTimeline: Decodable {
    struct Leg: Decodable { let action: String; let direction: String; let start: Int; let duration: Int }
    struct Plan: Decodable { let id: Int; let mask: Int; let slots: [String]; let frames: [MotionFrame]; let legs: [Leg]?; let frameIndices: [Int]? }
    let frameTable: [MotionFrame]?
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
        guard let value = plans.first(where: { $0.id == plan }) else { return nil }
        if let indices = value.frameIndices, !indices.isEmpty, let table = frameTable {
            let index = indices[max(0, Int(elapsed * Double(fps))) % indices.count]
            return table.indices.contains(index) ? table[index] : nil
        }
        guard !value.frames.isEmpty else { return nil }
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


