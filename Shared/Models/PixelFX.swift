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
    var localLevels: [SurvivorLocalLevel]? = nil
    var role: String? = nil
    var hitRadius: Double? = nil
    var hitDelay: Double? = nil
    var selectable: Bool { role == nil || role == "attack" || role == "support" }
    var roleTitle: String { role == "item" ? "拾取物品" : role == "decoration" ? "展示特效" : profile == .heal ? "辅助技能" : "攻击技能" }
    func radius(at level: Int) -> Double { (hitRadius ?? (profile == .projectile ? 12 : 40)) * (1 + Double(level-1)*0.08) }
    func damage(at level: Int) -> Double { profile == .heal ? 0 : (profile == .projectile ? 16 : 12)+Double(level)*7 }
    func cooldown(at level: Int, haste: Int = 0) -> Double {
        profile == .projectile ? max(0.3,1.1*pow(0.88,Double(haste))*pow(0.95,Double(level-1))) : max(duration+0.4,(6.5-Double(level)*0.35)*pow(0.92,Double(haste)))
    }
    func stats(at level: Int, haste: Int = 0, power: Double = 1) -> String {
        if localLevels != nil { return SurvivorLocalSkills.detail(id,level:level,haste:haste,power:power) }
        let level = max(1,min(5,level))
        let amount = profile == .heal ? "治疗 \(6+level*4)" : "伤害 \(Int(damage(at:level)*power)) · 半径 \(Int(radius(at:level)))"
        return amount + String(format:" · 冷却 %.2f秒",cooldown(at:level,haste:haste)) + (profile == .projectile ? " · \(1+(level-1)/2)发 · 穿透\(level>=4 ? 2:1)" : profile == .heal ? "" : " · 每0.65秒判定")
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
        case id, title, category, profile, loop, duration, description, role, localLevels
        case hitRadius = "hit_radius", hitDelay = "hit_delay"
        case categoryTitle = "category_title"
    }
    var upgrade: SurvivorUpgrade { .effect(id) }
}

struct PixelFXCast: Codable, Identifiable, Sendable {
    var clipID: String? = nil
    var targetID: UInt64? = nil
    var events: Set<Int>? = nil
    var angle: Double? = nil
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
