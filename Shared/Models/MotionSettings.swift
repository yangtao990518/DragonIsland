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
}

struct MotionTimeline: Decodable {
    struct Plan: Decodable { let id: Int; let mask: Int; let slots: [String]; let frames: [MotionFrame] }
    let fps: Int
    let period: Int
    let plans: [Plan]
    static let shared: MotionTimeline? = {
        guard let url = Bundle.main.url(forResource: "MotionTimeline", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MotionTimeline.self, from: data)
    }()
    func frame(plan: Int, elapsed: TimeInterval) -> MotionFrame? {
        guard let value = plans.first(where: { $0.id == plan }), !value.frames.isEmpty else { return nil }
        return value.frames[max(0, Int(elapsed * Double(fps))) % value.frames.count]
    }
}
