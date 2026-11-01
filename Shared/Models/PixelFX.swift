import Foundation

struct PixelFXSkill: Codable, Equatable, Identifiable, Sendable {
    enum Profile: String, Codable, Sendable {
        case projectile, zone, aura, heal, orbit
        var title: String {
            switch self {
            case .projectile: return "自动弹体"
            case .zone: return "范围法术"
            case .aura: return "护身灵环"
            case .heal: return "治疗祝福"
            case .orbit: return "环绕灵兽"
            }
        }
    }
    let id: String
    let title: String
    let category: String
    let categoryTitle: String
    let profile: Profile
    let loop: Bool
    let duration: Double
    let description: String
    enum CodingKeys: String, CodingKey {
        case id, title, category, profile, loop, duration, description
        case categoryTitle = "category_title"
    }
    var upgrade: SurvivorUpgrade { .effect(id) }
}

struct PixelFXCast: Codable, Identifiable, Sendable {
    let id: UInt64
    let skillID: String
    let profile: PixelFXSkill.Profile
    let level: Int
    var position: SurvivorVector
    var velocity: SurvivorVector
    let duration: Double
    let radius: Double
    let damage: Double
    var age = 0.0
    var nextPulse = 0.1
    var hitIDs: Set<UInt64> = []
}

struct PixelFXFeedback: Codable, Identifiable, Sendable {
    let id: UInt64
    let skillID: String
    let position: SurvivorVector
    let born: Double
}

/// Optional in old run snapshots; a legacy run is migrated explicitly by the
/// App when continuing in PixelFX mode, without touching chat/character data.
struct PixelFXBattleState: Codable, Sendable {
    let catalog: [PixelFXSkill]
    var pool: [String]
    var casts: [PixelFXCast] = []
    var feedback: [PixelFXFeedback] = []
    var cooldowns: [String: Double] = [:]
}
