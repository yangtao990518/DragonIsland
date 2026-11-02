import Foundation

/// Nov-2 confirmed library. Balance numbers are editable initial tuning, not
/// author-approved values. Visual events follow the supplied effect source.
enum SurvivorLocalSkills {
    static let ids = ["fireball","lightning","earth-spikes","stone-fist","boulder","quicksand","orbit-swords","seeking-swords"]
    static let supportIcons: [SurvivorUpgrade:String] = [.stride:"move-speed",.haste:"attack-speed",.power:"damage",.vitality:"vitality",.defense:"defense"]
    /// At most current+next for each weapon. Prewarm before a choice is made,
    /// rather than throwing away the live atlas set after each upgrade.
    static func warmClipIDs(skills: [PixelFXSkill], ranks: [String: Int]) -> [String] {
        skills.flatMap { skill -> [String] in
            let rank = max(0, min(5, ranks[skill.id, default: 0]))
            let levels = Set([max(1, rank), min(5, rank + 1)])
            return (skill.localLevels ?? []).filter { levels.contains($0.level) }.map(\.clipID)
        }
    }
    static func baseDamage(_ id:String, level:Int)->Double {
        let base:Double = id == "fireball" ? 34 : id == "quicksand" ? 12 : id == "orbit-swords" ? 16 : 32
        return base * (1+Double(level-1)*0.18)
    }
    static func cooldown(_ id:String, level:Int, haste:Int)->Double {
        let base:Double = id == "fireball" ? 1.3 : id == "lightning" ? 4.6 : id == "seeking-swords" ? 5.5 : 5
        return base / (1+Double(haste)*0.12)
    }
    static func detail(_ id:String,level:Int,haste:Int,power:Double)->String {
        let level=max(1,min(5,level))
        let property:String
        switch id {
        case "fireball": property="\(level)颗火球"+(level==5 ? " · 命中爆炸":"")
        case "lightning": property="\(level)道雷 · 选取半径\(100+(level-1)*25)%"+(level==5 ? " · 五芒星雷爆":"")
        case "earth-spikes": property="\(level)根岩柱"+(level==5 ? " · 五柱分别爆炸":"")
        case "stone-fist": property=level==5 ? "双拳 · 裂地震波":"单拳 · 尺寸\(Int([0.55,0.7,0.85,1][min(3,level-1)]*100))%"
        case "boulder": property=level==5 ? "主岩＋两颗伴岩":"单岩 · 尺寸\(Int([0.58,0.74,0.9,1.06][min(3,level-1)]*100))%"
        case "quicksand": property="持续减速牵引"+(level==5 ? " · 坍缩反喷":"")
        case "orbit-swords": property="\(level)柄剑 · 常驻正圆环绕"+(level==5 ? " · 周期月牙剑气":"")
        default: property="\(level)柄追踪剑气"+(level==5 ? " · 五剑合一":"")
        }
        let timing=id == "orbit-swords" ? " · 常驻" : String(format:" · 冷却%.2f秒",cooldown(id,level:level,haste:haste))
        return property+" · 伤害\(Int(baseDamage(id,level:level)*power))"+timing
    }
}

struct SurvivorLocalLevel: Codable, Equatable, Sendable {
    let level:Int
    let clipID:String
    let duration:Double
    let loop:Bool
}

struct SurvivorLocalCharacter: Codable, Sendable {
    let id:String
    let name:String
    let role:String
    let bodyAction:String
}

struct SurvivorMonsterShot: Codable, Identifiable, Sendable {
    let id:UInt64
    var position:SurvivorVector
    let velocity:SurvivorVector
    var remaining:Double
    let damage:Double
}

enum SurvivorGrassland {
    // ~16 landscape camera widths, finite square. Physics and minimap share it.
    static let halfSide = 6_400.0
    static let border = 96.0
    static let paths:[[SurvivorVector]] = [
        [.init(x:-5900,y:-2700),.init(x:-3600,y:-1100),.init(x:-1400,y:-300),.init(x:200,y:700),.init(x:2900,y:1700),.init(x:5700,y:3500)],
        [.init(x:-2500,y:-5700),.init(x:-1900,y:-3300),.init(x:-900,y:-500),.init(x:1600,y:2200),.init(x:2600,y:5600)],
        [.init(x:-5800,y:4300),.init(x:-3300,y:3000),.init(x:-900,y:1100),.init(x:1600,y:-1100),.init(x:4000,y:-3300),.init(x:5800,y:-4700)]
    ]
    static func clamp(_ p:SurvivorVector, margin:Double = SurvivorGrassland.border)->SurvivorVector {
        let edge=halfSide-margin
        return .init(x:max(-edge,min(edge,p.x)),y:max(-edge,min(edge,p.y)))
    }
}
