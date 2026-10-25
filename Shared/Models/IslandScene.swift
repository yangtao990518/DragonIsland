import Foundation

enum IslandScene: String, Codable, CaseIterable, Identifiable {
    case black, meadow, night
    var id: String { rawValue }
    var title: String {
        switch self {
        case .black: return "经典黑色"
        case .meadow: return "小小草地"
        case .night: return "月下星夜"
        }
    }
    var asset: String { "IslandScene_\(rawValue)" }
    var wideAsset: String { "IslandSceneWide_\(rawValue)" }
    var fontPrefix: String {
        switch self {
        case .black: return "mAIverse"
        case .meadow: return "mAIverseMeadow"
        case .night: return "mAIverseNight"
        }
    }
    static func resolve(_ value: String?) -> IslandScene { value.flatMap(Self.init(rawValue:)) ?? .black }
    static func load() -> IslandScene { resolve(UserDefaults.standard.string(forKey: "islandScene")) }
    func save() { UserDefaults.standard.set(rawValue, forKey: "islandScene") }
}
