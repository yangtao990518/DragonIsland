import Foundation

struct SurvivorVector: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    static let zero = Self(x: 0, y: 0)
    var length: Double { hypot(x, y) }
    var normalized: Self { length > 0.000001 ? self * (1 / length) : .zero }
    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b) }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y }
}

struct SurvivorUpgrade: RawRepresentable, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    static let thunder = Self(rawValue: "thunder"), bubble = Self(rawValue: "bubble")
    static let power = Self(rawValue: "power"), haste = Self(rawValue: "haste")
    static let stride = Self(rawValue: "stride"), magnet = Self(rawValue: "magnet")
    static let vitality = Self(rawValue: "vitality"), mend = Self(rawValue: "mend")
    static let defense = Self(rawValue:"defense")
    static let allCases: [Self] = [.thunder,.bubble,.power,.haste,.stride,.magnet,.vitality,.mend]
    static func effect(_ id: String) -> Self { .init(rawValue: "fx:" + id) }
    var effectID: String? { rawValue.hasPrefix("fx:") ? String(rawValue.dropFirst(3)) : nil }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thunder: return "紫霄雷"
        case .bubble: return "水泡术"
        case .power: return "强攻"
        case .haste: return "迅击"
        case .stride: return "疾行"
        case .magnet: return "聚灵"
        case .vitality: return "生机"
        case .defense: return "坚守"
        case .mend: return "回春"
        default: return effectID ?? rawValue
        }
    }
    var symbol: String {
        switch self {
        case .thunder: return "bolt.fill"
        case .bubble: return "drop.fill"
        case .power: return "sparkles"
        case .haste: return "timer"
        case .stride: return "wind"
        case .magnet: return "circle.dotted.circle.fill"
        case .vitality: return "heart.fill"
        case .mend: return "cross.case.fill"
        default: return "sparkles"
        }
    }
    var maximum: Int {
        switch self {
        case .thunder, .bubble, .power, .haste: return 5
        case .stride, .magnet, .vitality, .defense: return 5
        case .mend: return Int.max
        default: return 5
        }
    }
    func detail(current: Int) -> String {
        switch self {
        case .thunder: return current == 0 ? "自动召唤雷阵，持续打击前方敌人" : "雷阵提升至\(current + 1)级，扩大范围并增强伤害"
        case .bubble: return "增强自动水泡；3级、5级增加一枚弹体"
        case .power: return "全部攻击伤害提高14%"
        case .haste: return "攻击速度增加12%，所有有冷却的攻击技能释放更快"
        case .defense: return "每级增加2点护甲，承受伤害最低为1"
        case .stride: return "移动速度提高10%"
        case .magnet: return "扩大经验拾取和吸引范围"
        case .vitality: return "生命上限增加20，并回复20点生命"
        case .mend: return "立即回复35点生命"
        default: return "自动释放，升级增强伤害、范围或弹体数量"
        }
    }
}

enum SurvivorEnemyKind: String, Codable, Sendable { case demon, mushroom, elite, boss }
enum SurvivorOutcome: String, Codable, Sendable { case victory, defeat }

struct SurvivorEnemy: Codable, Identifiable, Sendable {
    var variant: String? = nil
    var born: Double? = nil
    var nextAttack: Double? = nil
    var slowUntil: Double? = nil
    let id: UInt64
    let kind: SurvivorEnemyKind
    var position: SurvivorVector
    var health: Double
    let maximumHealth: Double
    let speed: Double
    let radius: Double
    var facingLeft = true
    var hitUntil: Double = 0
}

struct SurvivorBubble: Codable, Identifiable, Sendable {
    let id: UInt64
    var position: SurvivorVector
    let velocity: SurvivorVector
    var life: Double
    let damage: Double
    let radius: Double
}

struct SurvivorExperience: Codable, Identifiable, Sendable {
    let id: UInt64
    var position: SurvivorVector
    var value: Int
}

struct SurvivorThunder: Codable, Identifiable, Sendable {
    let id: UInt64
    let position: SurvivorVector
    let level: Int
    let duration: Double
    let radius: Double
    let damage: Double
    var age: Double = 0
    var nextPulse: Double = 0.12
}

private struct SurvivorRandom: Codable, Sendable {
    var state: UInt64
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9007199254740992
    }
    mutating func shuffle<T>(_ input: [T]) -> [T] {
        var values = input
        guard values.count > 1 else { return values }
        for i in stride(from: values.count - 1, through: 1, by: -1) {
            values.swapAt(i, min(i, Int(unit() * Double(i + 1))))
        }
        return values
    }
}

/// Native-renderer-independent combat rules. Particles are visual only; damage
/// uses these stable circles and swept projectile paths, never texture alpha.
struct SurvivorBattle: Codable, Sendable {
    private(set) var configuration: SurvivorRunConfiguration
    private(set) var clock: SurvivorRunClock
    private(set) var player = SurvivorVector.zero
    private(set) var facingLeft = true
    private(set) var moving = false
    private(set) var health: Double = 100
    private(set) var level = 1
    private(set) var experience = 0
    private(set) var kills = 0
    private(set) var upgrades: [SurvivorUpgrade: Int] = [.bubble: 1]
    private(set) var choices: [SurvivorUpgrade] = []
    private(set) var enemies: [SurvivorEnemy] = []
    private(set) var bubbles: [SurvivorBubble] = []
    private(set) var drops: [SurvivorExperience] = []
    private(set) var thunders: [SurvivorThunder] = []
    private(set) var outcome: SurvivorOutcome?
    private(set) var pixelFX: PixelFXBattleState?
    private(set) var monsterShots: [SurvivorMonsterShot]? = nil
    let thunderDuration: Double
    private var random: SurvivorRandom
    private var nextID: UInt64 = 1
    private var spawnIn: Double = 0.5
    private var bubbleIn: Double = 0.2
    private var thunderIn: Double = 0.2
    private var invincibleUntil: Double = 0
    private var bossSpawned = false

    var usesLocalSkills: Bool { pixelFX?.catalog.first?.localLevels != nil }
    var maximumHealth: Double { 100 + Double(rank(.vitality)) * 20 }
    var experienceNeeded: Int { 20 + level * 12 }
    var damageMultiplier: Double { 1 + Double(rank(.power)) * 0.14 }
    var playerSpeed: Double { 135 * (1 + Double(rank(.stride)) * 0.10) }
    var pickupRadius: Double { 30 + Double(rank(.magnet)) * 18 }
    var absorbRadius: Double { 100 + Double(rank(.magnet)) * 50 }
    var playerIsInvincible: Bool { clock.elapsed < invincibleUntil }

    init(configuration: SurvivorRunConfiguration = .standard, seed: UInt64 = 1,
         thunderDuration: Double = 4.096009) throws {
        try configuration.validate()
        guard thunderDuration.isFinite, thunderDuration > 0, thunderDuration <= 20 else {
            throw SurvivorRuleError.invalidConfiguration
        }
        self.configuration = configuration
        self.clock = try SurvivorRunClock(duration: configuration.duration)
        self.random = SurvivorRandom(state: seed)
        self.thunderDuration = thunderDuration
        clock.start()
    }

    func rank(_ upgrade: SurvivorUpgrade) -> Int { upgrades[upgrade, default: 0] }
    mutating func pause(_ reason: SurvivorRunClock.PauseReason) { clock.pause(reason); moving = false }
    mutating func resume(_ reason: SurvivorRunClock.PauseReason) { clock.resume(reason) }
    private mutating func identifier() -> UInt64 { defer { nextID += 1 }; return nextID }

    mutating func advance(by delta: Double, movement: SurvivorVector) throws {
        guard delta.isFinite, delta >= 0, movement.x.isFinite, movement.y.isFinite else {
            throw SurvivorRuleError.invalidDelta
        }
        var remaining = min(delta, clock.remaining)
        while remaining > 0.000000001, clock.running, outcome == nil {
            let step = min(1.0 / 60, remaining)
            try tick(step, movement: movement)
            remaining -= step
        }
    }

    private mutating func tick(_ delta: Double, movement: SurvivorVector) throws {
        try clock.advance(by: delta)
        if clock.finished { outcome = .victory; moving = false; return }
        let direction = movement.length > 1 ? movement.normalized : movement
        moving = direction.length > 0.01
        player = player + direction * (playerSpeed * delta)
        if usesLocalSkills { player = SurvivorGrassland.clamp(player) }
        if abs(direction.x) > 0.01 { facingLeft = direction.x < 0 }

        spawnIn -= delta
        if let stage = configuration.stage(at: clock.elapsed), spawnIn <= 0 {
            spawnIn += stage.spawnInterval
            if enemies.count < stage.enemyLimit {
                let batch = usesLocalSkills ? min(stage.enemyLimit-enemies.count,clock.elapsed < 60 ? 3 : clock.elapsed < 300 ? 5 : clock.elapsed < 840 ? 8 : 12) : 1
                for _ in 0..<batch {
                    let angle = random.unit() * .pi * 2
                    let distance = 520 + random.unit() * 130
                    let kind: SurvivorEnemyKind = usesLocalSkills && clock.elapsed > 240 && random.unit() < 0.035 ? .elite : random.unit() < 0.42 ? .mushroom : .demon
                    let position = player + SurvivorVector(x: cos(angle), y: sin(angle)) * distance
                    _ = spawnEnemy(at: usesLocalSkills ? SurvivorGrassland.clamp(position) : position, kind: kind)
                }
            }
        }
        if !bossSpawned, clock.elapsed >= configuration.duration * 0.90 {
            bossSpawned = true
            _ = spawnEnemy(at: player + .init(x: 0, y: 480), kind: .boss)
        }
        for i in enemies.indices where enemies[i].health > 0 {
            let toPlayer = player - enemies[i].position
            if abs(toPlayer.x) > 0.5 { enemies[i].facingLeft = toPlayer.x < 0 }
            let ranged = usesLocalSkills && (enemies[i].variant?.contains("R2C") == true || enemies[i].variant?.contains("R4C") == true)
            let phase=(clock.elapsed-(enemies[i].born ?? 0)).truncatingRemainder(dividingBy:4.016667)
            let windingUp=usesLocalSkills && enemies[i].kind == .boss && phase>1.4 && phase<2.85
            let advance = windingUp ? 0 : ranged && toPlayer.length < 220 ? 0.15 : 1.0
            let slow = clock.elapsed < (enemies[i].slowUntil ?? 0) ? 0.45 : 1.0
            enemies[i].position = enemies[i].position + toPlayer.normalized * (enemies[i].speed * delta * slow * advance)
            if usesLocalSkills { enemies[i].position=SurvivorGrassland.clamp(enemies[i].position) }
        }
        separateEnemies(SurvivorEnemyGrid(enemies))
        if usesLocalSkills { for i in enemies.indices {enemies[i].position=SurvivorGrassland.clamp(enemies[i].position)} }
        // Separation changes positions; damage queries need the updated cells.
        let grid = SurvivorEnemyGrid(enemies)

        bubbleIn -= delta
        if rank(.bubble) > 0, bubbleIn <= 0, let target = nearestEnemy() {
            fireBubbles(toward: target.position)
            bubbleIn = max(0.18, 0.85 * pow(0.88, Double(rank(.haste))) * pow(0.95, Double(rank(.bubble)-1)))
        }
        thunderIn -= delta
        if rank(.thunder) > 0, thunderIn <= 0, thunders.count < 2, let target = nearestEnemy() {
            let thunderRank = rank(.thunder)
            let effectID = identifier()
            thunders.append(.init(id: effectID, position: target.position, level: thunderRank,
                                  duration: thunderDuration, radius: 62 + Double(thunderRank) * 17,
                                  damage: (20 + Double(thunderRank) * 12) * damageMultiplier))
            thunderIn = max(thunderDuration + 0.5, 8 - Double(thunderRank) * 0.5 - Double(self.rank(.haste)) * 0.2)
        }
        // Grid indices remain valid until dead enemies are removed at the end.
        for i in bubbles.indices {
            let start = bubbles[i].position
            let end = start + bubbles[i].velocity * delta
            bubbles[i].position = end; bubbles[i].life -= delta
            let candidates = grid.query(from: start, to: end, margin: 50)
            let target = candidates.filter { index in
                enemies[index].health > 0 && Self.segmentDistance(enemies[index].position, start, end)
                    <= enemies[index].radius + bubbles[i].radius
            }.min { (enemies[$0].position - start).length < (enemies[$1].position - start).length }
            if let target {
                enemies[target].health -= bubbles[i].damage
                enemies[target].hitUntil = clock.elapsed + 0.12
                bubbles[i].life = 0
            }
        }
        bubbles.removeAll { $0.life <= 0 }
        for i in thunders.indices {
            thunders[i].age += delta
            while thunders[i].age >= thunders[i].nextPulse, thunders[i].nextPulse < thunders[i].duration {
                thunders[i].nextPulse += 0.75
                let effect = thunders[i]
                for index in grid.query(from: effect.position, to: effect.position, margin: effect.radius + 45) {
                    if enemies[index].health > 0,
                       (enemies[index].position - effect.position).length <= effect.radius + enemies[index].radius {
                        enemies[index].health -= effect.damage
                        enemies[index].hitUntil = clock.elapsed + 0.15
                    }
                }
            }
        }
        thunders.removeAll { $0.age >= $0.duration }
        if usesLocalSkills { advanceLocalSkills(delta,grid:grid); advanceLocalMonsters(delta) }
        else if pixelFX != nil { advancePixelFX(delta, grid: grid) }
        for enemy in enemies where enemy.health <= 0 {
            kills += 1
            emitPixelFeedback("spawn-poof", at: enemy.position)
            let value = enemy.kind == .boss ? 500 : enemy.kind == .elite ? 80 : enemy.kind == .demon ? 12 : 18
            if drops.count < 350 {
                let dropID = identifier()
                drops.append(.init(id: dropID, position: enemy.position, value: value))
            } else if let index = drops.indices.min(by: {
                (drops[$0].position - enemy.position).length < (drops[$1].position - enemy.position).length
            }) { drops[index].value += value }
        }
        enemies.removeAll { $0.health <= 0 }
        // Recycle remote pursuers so long straight movement cannot fill the
        // whole spawn budget with enemies permanently far behind the camera.
        for i in enemies.indices where (enemies[i].position - player).length > 950 {
            let angle = random.unit() * .pi * 2
            let recycled=player + SurvivorVector(x: cos(angle), y: sin(angle)) * 600
            enemies[i].position = usesLocalSkills ? SurvivorGrassland.clamp(recycled) : recycled
        }
        for enemy in enemies where (enemy.position - player).length <= enemy.radius + 13 {
            takeDamage(enemy.kind == .boss ? 18 : 8)
        }
        for i in drops.indices {
            let distance = (player - drops[i].position).length
            if distance <= pickupRadius {
                experience += drops[i].value; drops[i].value = 0
                emitPixelFeedback("pickups-collect-burst", at: player)
            }
            else if distance < absorbRadius {
                drops[i].position = drops[i].position + (player - drops[i].position).normalized * min(distance, 300 * delta)
            }
        }
        drops.removeAll { $0.value == 0 }
        if health <= 0 { outcome = .defeat; moving = false; return }
        offerUpgradeIfNeeded()
    }

    @discardableResult mutating func spawnEnemy(at position: SurvivorVector, kind: SurvivorEnemyKind) -> UInt64 {
        let enemyID = identifier()
        let hp = kind == .boss ? 1600.0 : kind == .elite ? 220 : (kind == .demon ? 30.0 : 45) + clock.elapsed * 0.055
        let speed = kind == .boss ? 47.0 : kind == .demon ? 56.0 : 42.0
        enemies.append(.init(id: enemyID, kind: kind, position: usesLocalSkills ? SurvivorGrassland.clamp(position) : position, health: hp, maximumHealth: hp,
                             speed: speed + min(22, clock.elapsed / 80), radius: kind == .boss ? 35 : 14))
        if usesLocalSkills {
            let group:String
            if kind == .boss { group="group02-elites-boss-R2C2" }
            else if kind == .elite { group=["group02-elites-boss-R1C1","group02-elites-boss-R1C2","group02-elites-boss-R2C1"][Int(random.unit()*3)%3] }
            else {
                let rows=clock.elapsed < 90 ? 1 : clock.elapsed < 210 ? 2 : clock.elapsed < 360 ? 3 : 4
                let row=1+Int(random.unit()*Double(rows))%rows, column=1+Int(random.unit()*4)%4
                group="group01-skeleton-roles-R\(row)C\(column)"
            }
            enemies[enemies.count-1].variant="skeleton-"+group
            enemies[enemies.count-1].born=clock.elapsed
            enemies[enemies.count-1].nextAttack=clock.elapsed+(kind == .boss ? 2.55:group=="group02-elites-boss-R2C1" ? 2.4:2+random.unit()*2)
        }
        return enemyID
    }

    mutating func takeDamage(_ damage: Double) {
        guard clock.running, clock.elapsed >= invincibleUntil, outcome == nil, damage.isFinite, damage > 0 else { return }
        health = max(0, health - max(1,damage-Double(rank(.defense))*2))
        emitPixelFeedback("impacts-hit-spark", at: player)
        invincibleUntil = clock.elapsed + 0.7
    }

    /// Awarding experience is shared by orb pickup and future stage rewards.
    mutating func awardExperience(_ value: Int) {
        guard outcome == nil, value > 0 else { return }
        experience += value
        offerUpgradeIfNeeded()
    }

    private mutating func offerUpgradeIfNeeded() {
        guard choices.isEmpty, experience >= experienceNeeded, outcome == nil else { return }
        var candidates = SurvivorUpgrade.allCases
        if let state = pixelFX {
            let equipped = upgrades.keys.filter { $0.effectID != nil && rank($0) > 0 }.count
            candidates = usesLocalSkills ? [.power,.haste,.stride,.vitality,.defense] : [.power,.haste,.stride,.magnet,.vitality,.mend]
            candidates += state.catalog.filter { state.pool.contains($0.id) && (equipped < 6 || rank($0.upgrade) > 0) }.map(\.upgrade)
        }
        let available = candidates.filter {
            rank($0) < $0.maximum && ($0 != .mend || health < maximumHealth)
        }
        var options = random.shuffle(available)
        if pixelFX == nil, rank(.thunder) == 0 {
            options.removeAll { $0 == .thunder }; options.insert(.thunder, at: 0)
        }
        if pixelFX != nil, let learned = options.first(where: { $0.effectID != nil && rank($0) > 0 }) {
            options.removeAll { $0 == learned }; options.insert(learned, at: 0)
        }
        if options.isEmpty { options = [.mend] }
        choices = Array(options.prefix(3))
        clock.pause(.upgrade); moving = false
    }

    @discardableResult mutating func choose(_ upgrade: SurvivorUpgrade) -> Bool {
        guard choices.contains(upgrade), clock.pauseReasons.contains(.upgrade), outcome == nil else { return false }
        let required = experienceNeeded
        guard experience >= required, rank(upgrade) < upgrade.maximum else { return false }
        if upgrade == .mend { health = min(maximumHealth, health + 35) }
        else {
            upgrades[upgrade, default: 0] += 1
            if upgrade == .vitality { health = min(maximumHealth, health + 20) }
            if upgrade == .thunder { thunderIn = 0.1 }
        }
        emitPixelFeedback(upgrade == .mend || upgrade == .vitality ? "holy-heal" : "ui-level-up", at: player)
        experience -= required; level += 1; choices = []
        clock.resume(.upgrade)
        offerUpgradeIfNeeded() // Banked XP may earn another choice, still paused.
        return true
    }

    private func nearestEnemy() -> SurvivorEnemy? {
        enemies.filter { $0.health > 0 && ($0.position - player).length < 650 }
            .min { ($0.position - player).length < ($1.position - player).length }
    }

    private mutating func fireBubbles(toward position: SurvivorVector) {
        guard bubbles.count < 90 else { return }
        let direction = (position - player).normalized
        let count = rank(.bubble) >= 5 ? 3 : rank(.bubble) >= 3 ? 2 : 1
        let base = atan2(direction.y, direction.x)
        for index in 0..<count {
            let angle = base + (Double(index) - Double(count-1)/2) * 0.14
            let vector = SurvivorVector(x: cos(angle), y: sin(angle))
            let bubbleID = identifier()
            bubbles.append(.init(id: bubbleID, position: player + vector * 20,
                                 velocity: vector * 290, life: 2.3,
                                 damage: (16 + Double(rank(.bubble)-1)*5) * damageMultiplier,
                                 radius: 5 + Double(rank(.bubble))*0.4))
        }
    }

    private mutating func separateEnemies(_ grid: SurvivorEnemyGrid) {
        for i in enemies.indices where enemies[i].health > 0 {
            let point = enemies[i].position
            for j in grid.query(from: point, to: point, margin: 70) where j > i && enemies[j].health > 0 {
                let offset = enemies[j].position - enemies[i].position
                let minimum = enemies[i].radius + enemies[j].radius
                if offset.length < minimum {
                    let unit = offset.length < 0.001 ? SurvivorVector(x: 1, y: 0) : offset.normalized
                    let push = unit * ((minimum - offset.length) * 0.20)
                    enemies[i].position = enemies[i].position - push
                    enemies[j].position = enemies[j].position + push
                }
            }
        }
    }

    static func segmentDistance(_ point: SurvivorVector, _ start: SurvivorVector, _ end: SurvivorVector) -> Double {
        let delta = end - start
        let denominator = delta.dot(delta)
        let t = denominator > 0 ? min(1, max(0, (point-start).dot(delta) / denominator)) : 0
        return (point - (start + delta * t)).length
    }
}

extension SurvivorBattle {
    var pixelSkills: [PixelFXSkill] { pixelFX?.catalog ?? [] }
    var equippedPixelSkills: [PixelFXSkill] { pixelSkills.filter { $0.selectable && rank($0.upgrade) > 0 } }
    func title(for upgrade: SurvivorUpgrade) -> String {
        pixelSkills.first { $0.upgrade == upgrade }?.title ?? upgrade.title
    }
    func detail(for upgrade: SurvivorUpgrade) -> String {
        guard let skill = pixelSkills.first(where: { $0.upgrade == upgrade }) else { return upgrade.detail(current: rank(upgrade)) }
        let level = rank(upgrade)
        let next = skill.stats(at:level+1,haste:rank(.haste),power:damageMultiplier)
        return level == 0 ? "学习："+next : "当前："+skill.stats(at:level,haste:rank(.haste),power:damageMultiplier)+"\n升级："+next
    }
    mutating func configurePixelFX(_ catalog: [PixelFXSkill], starter: String) throws {
        guard !catalog.isEmpty, Set(catalog.map(\.id)).count == catalog.count,
              catalog.contains(where: { $0.id == starter && $0.selectable }),
              catalog.allSatisfy({ $0.duration.isFinite && $0.duration > 0 && $0.duration <= 20 }) else {
            throw SurvivorRuleError.invalidConfiguration
        }
        // Continuing old build-21 runs keeps time, health, XP and passive ranks.
        let previous = upgrades.filter { $0.key.effectID != nil }
        upgrades = upgrades.filter { $0.key != .bubble && $0.key != .thunder && $0.key.effectID == nil }
        for (key,value) in previous where catalog.contains(where: { $0.upgrade == key && $0.selectable }) { upgrades[key] = value }
        if !upgrades.keys.contains(where: { $0.effectID != nil }) { upgrades[.effect(starter)] = 1 }
        if catalog.first?.localLevels != nil {
            if clock.duration == SurvivorRunConfiguration.standard.duration {configuration = .standard}
            for i in enemies.indices where enemies[i].variant == nil {
                let role=enemies[i].kind == .boss ? "group02-elites-boss-R2C2" : enemies[i].kind == .elite ? "group02-elites-boss-R1C1" : "group01-skeleton-roles-R1C\(1+Int(enemies[i].id%4))"
                enemies[i].variant="skeleton-"+role;enemies[i].born=clock.elapsed;enemies[i].nextAttack=clock.elapsed+2.55
            }
        }
        monsterShots = nil
        pixelFX = PixelFXBattleState(catalog: catalog, pool: catalog.filter(\.selectable).map(\.id))
        bubbles = []; thunders = []; choices = []
        clock.resume(.upgrade); offerUpgradeIfNeeded()
    }
    @discardableResult mutating func choosePixelFXFromLibrary(_ id: String) -> Bool {
        let upgrade = SurvivorUpgrade.effect(id)
        guard clock.pauseReasons.contains(.upgrade), let state = pixelFX,
              state.catalog.contains(where: { $0.id == id && $0.selectable }), rank(upgrade) < 5,
              rank(upgrade) > 0 || equippedPixelSkills.count < 6 else { return false }
        if !choices.contains(upgrade) { choices.append(upgrade) }
        return choose(upgrade)
    }
    private mutating func emitPixelFeedback(_ id: String, at position: SurvivorVector) {
        guard pixelFX != nil, pixelSkills.contains(where: { $0.id == id }) else { return }
        let eventID = identifier()
        pixelFX?.feedback.append(.init(id: eventID, skillID: id, position: position, born: clock.elapsed))
        if let count = pixelFX?.feedback.count, count > 24 { pixelFX?.feedback.removeFirst(count-24) }
    }
    fileprivate mutating func advancePixelFX(_ delta: Double, grid: SurvivorEnemyGrid) {
        guard var state = pixelFX else { return }
        let now = clock.elapsed
        let feedbackDurations = state.feedback.map { event in state.catalog.first { $0.id == event.skillID }?.duration ?? 4 }
        state.feedback = zip(state.feedback,feedbackDurations).filter { now-$0.0.born < $0.1 }.map { $0.0 }
        let equipped = state.catalog.filter { $0.selectable && rank($0.upgrade) > 0 }
        for skill in equipped {
            state.cooldowns[skill.id, default: 0] -= delta
            guard state.cooldowns[skill.id, default: 0] <= 0, state.casts.count < 16 else { continue }
            guard let target = nearestEnemy() else { continue }
            if skill.profile != .projectile && (target.position-player).length > 340 { continue }
            let level = rank(skill.upgrade), direction = (target.position-player).normalized
            let duration = skill.profile == .projectile && skill.loop ? 2.5 : skill.duration
            let speed = max(240, (target.position-player).length / max(0.15,duration-0.15))
            let count = skill.profile == .projectile ? 1+(level-1)/2 : 1
            for index in 0..<count {
                let angle = atan2(direction.y,direction.x) + (Double(index)-Double(count-1)/2)*0.14
                let velocity = skill.profile == .projectile ? SurvivorVector(x: cos(angle),y: sin(angle))*speed : .zero
                let position = skill.profile == .zone ? target.position : player
                let castID = identifier()
                state.casts.append(.init(id: castID,skillID:skill.id,profile:skill.profile,level:level,position:position,
                    velocity:velocity,duration:duration,radius:skill.radius(at:level),
                    damage:skill.damage(at:level)*damageMultiplier,nextPulse:skill.hitDelay ?? 0.1))
            }
            if skill.profile == .heal { health = min(maximumHealth,health+6+Double(level)*4) }
            state.cooldowns[skill.id] = skill.cooldown(at:level,haste:rank(.haste))
        }
        for index in state.casts.indices {
            state.casts[index].age += delta
            let old = state.casts[index].position
            switch state.casts[index].profile {
            case .projectile: state.casts[index].position = old + state.casts[index].velocity*delta
            case .aura,.heal: state.casts[index].position = player
            case .orbit:
                let angle = clock.elapsed*2.2+Double(index)*2.399
                state.casts[index].position = player + SurvivorVector(x:cos(angle),y:sin(angle))*(55+Double(state.casts[index].level)*9)
            case .zone: break
            }
            var cast = state.casts[index]
            if cast.profile == .projectile {
                let hits = grid.query(from:old,to:cast.position,margin:55).filter {
                    enemies[$0].health > 0 && !cast.hitIDs.contains(enemies[$0].id) && Self.segmentDistance(enemies[$0].position,old,cast.position) <= cast.radius+enemies[$0].radius
                }.sorted { (enemies[$0].position-old).length < (enemies[$1].position-old).length }
                for enemy in hits {
                    enemies[enemy].health -= cast.damage; enemies[enemy].hitUntil = clock.elapsed+0.12
                    cast.hitIDs.insert(enemies[enemy].id)
                    let eventID = identifier()
                    state.feedback.append(.init(id:eventID,skillID:"impacts-hit-spark",position:enemies[enemy].position,born:clock.elapsed))
                    if cast.hitIDs.count >= (cast.level >= 4 ? 2 : 1) { cast.age = cast.duration; break }
                }
            } else if cast.profile != .heal && cast.age >= cast.nextPulse && cast.age < cast.duration {
                cast.nextPulse += 0.65
                for enemy in grid.query(from:cast.position,to:cast.position,margin:cast.radius+45) where enemies[enemy].health > 0 {
                    if (enemies[enemy].position-cast.position).length <= cast.radius+enemies[enemy].radius {
                        enemies[enemy].health -= cast.damage; enemies[enemy].hitUntil = clock.elapsed+0.12
                    }
                }
            }
            state.casts[index] = cast
        }
        state.casts.removeAll { $0.age >= $0.duration }
        if state.feedback.count > 10 { state.feedback.removeFirst(state.feedback.count-10) }
        pixelFX = state
    }
}

fileprivate struct SurvivorEnemyGrid {
    private struct Cell: Hashable { let x: Int; let y: Int }
    private var cells: [Cell: [Int]] = [:]
    private let side = 80.0
    init(_ enemies: [SurvivorEnemy]) {
        for (index, enemy) in enemies.enumerated() where enemy.health > 0 {
            let cell = Cell(x: Int(floor(enemy.position.x / side)), y: Int(floor(enemy.position.y / side)))
            cells[cell, default: []].append(index)
        }
    }
    func query(from start: SurvivorVector, to end: SurvivorVector, margin: Double) -> [Int] {
        let left = Int(floor((min(start.x,end.x)-margin)/side))
        let right = Int(floor((max(start.x,end.x)+margin)/side))
        let bottom = Int(floor((min(start.y,end.y)-margin)/side))
        let top = Int(floor((max(start.y,end.y)+margin)/side))
        var result: [Int] = []
        for x in left...right { for y in bottom...top { result += cells[Cell(x:x,y:y)] ?? [] } }
        return result
    }
}


extension SurvivorBattle {
    @discardableResult mutating func chooseLocalSupport(_ upgrade:SurvivorUpgrade)->Bool {
        guard usesLocalSkills,clock.pauseReasons.contains(.upgrade),SurvivorLocalSkills.supportIcons[upgrade] != nil,rank(upgrade)<upgrade.maximum else{return false}
        if !choices.contains(upgrade){choices.append(upgrade)}
        return choose(upgrade)
    }

    /// Confirmed Nov-2 behavior. Rendering uses the same asset event coordinates.
    fileprivate mutating func advanceLocalSkills(_ delta:Double,grid:SurvivorEnemyGrid) {
        guard var state=pixelFX else { return }
        let now=clock.elapsed
        state.feedback.removeAll { now-$0.born>1.6 }
        let learned=state.catalog.filter { rank($0.upgrade)>0 }
        for skill in learned {
            let level=rank(skill.upgrade)
            if skill.id == "orbit-swords" {
                if !state.casts.contains(where:{$0.skillID==skill.id}) {
                    state.casts.append(.init(clipID:"orbit-swords-lv\(level)",id:identifier(),skillID:skill.id,profile:.orbit,level:level,position:player,velocity:.zero,duration:1e9,radius:105,damage:SurvivorLocalSkills.baseDamage(skill.id,level:level)*damageMultiplier,age:now))
                }
                continue
            }
            state.cooldowns[skill.id,default:0]-=delta
            guard state.cooldowns[skill.id,default:0]<=0,state.casts.count<48,let target=nearestEnemy(),(target.position-player).length<520 else { continue }
            let damage=SurvivorLocalSkills.baseDamage(skill.id,level:level)*damageMultiplier
            let duration=skill.localLevels?.first(where:{$0.level==level})?.duration ?? 3.5
            if skill.id == "fireball" || skill.id == "seeking-swords" {
                let candidates=enemies.filter{$0.health>0 && ($0.position-player).length<520}.sorted{($0.position-player).length<($1.position-player).length}
                for i in 0..<level {
                    let aim=candidates[i%candidates.count]
                    let angle=atan2(aim.position.y-player.y,aim.position.x-player.x)+(Double(i)-Double(level-1)/2)*0.04
                    let speed=skill.id == "fireball" ? 300.0:330
                    let clip=skill.id == "fireball" ? "fireball-flight":"seeking-flight"
                    state.casts.append(.init(clipID:clip,targetID:aim.id,id:identifier(),skillID:skill.id,profile:.projectile,level:level,position:player,velocity:.init(x:cos(angle)*speed,y:sin(angle)*speed),duration:2,radius:skill.id == "fireball" ? 9:7,damage:damage,age:-Double(i)*0.055))
                }
                if skill.id == "seeking-swords" && level==5 {
                    state.casts.append(.init(clipID:"seeking-merged",targetID:target.id,id:identifier(),skillID:"seeking-merged",profile:.projectile,level:5,position:player,velocity:(target.position-player).normalized*390,duration:3.4,radius:17,damage:damage*2.5,age:-3.24))
                    state.casts.append(.init(clipOffset:2.4,clipID:"seeking-swords-lv5",id:identifier(),skillID:"seeking-charge",profile:.aura,level:5,position:player+SurvivorVector(x:72,y:0),velocity:.zero,duration:0.84,radius:0,damage:0,age:-2.4))
                }
            } else if skill.id == "lightning" {
                let radius=42*(1+Double(level-1)*0.25)
                let candidates=enemies.filter{enemy in let d=enemy.position-target.position;return enemy.health>0 && pow(d.x/radius,2)+pow(d.y/(radius*0.34),2)<=1}.sorted{($0.position-target.position).length<($1.position-target.position).length}
                for i in 0..<level {
                    let angle=Double(i)*2*Double.pi/Double(level)
                    let at=i<candidates.count ? candidates[i].position : target.position+SurvivorVector(x:cos(angle)*radius*0.65,y:sin(angle)*radius*0.65*0.34)
                    state.casts.append(.init(clipID:"lightning-lv1",events:[],id:identifier(),skillID:skill.id,profile:.zone,level:level,position:at,velocity:.zero,duration:1.817,radius:12,damage:damage,age:-Double(i)*0.025,nextPulse:0.5))
                }
                if level==5 {
                    state.casts.append(.init(clipID:"lightning-explosion",events:[],id:identifier(),skillID:"lightning-explosion",profile:.zone,level:5,position:target.position,velocity:.zero,duration:1.817,radius:84,damage:damage*1.6,age:-0.78,nextPulse:0.42))
                }
            } else {
                state.casts.append(.init(clipID:"\(skill.id)-lv\(level)",events:[],id:identifier(),skillID:skill.id,profile:.zone,level:level,position:target.position,velocity:.zero,duration:duration,radius:50,damage:damage))
            }
            state.cooldowns[skill.id]=SurvivorLocalSkills.cooldown(skill.id,level:level,haste:rank(.haste))
        }
        for index in state.casts.indices {
            var c=state.casts[index];c.age+=delta
            if c.age<0 { state.casts[index]=c;continue }
            if c.profile == .projectile {
                let old=c.position
                if c.skillID.hasPrefix("seeking"),let target=enemies.first(where:{$0.id==c.targetID && $0.health>0}) {
                    let desired=(target.position-c.position).normalized*c.velocity.length
                    c.velocity=c.velocity*(1-min(1,delta*7))+desired*min(1,delta*7)
                }
                c.position=c.position+c.velocity*delta;c.angle=atan2(c.velocity.y,c.velocity.x)
                let hit=grid.query(from:old,to:c.position,margin:c.radius+45).filter { enemies[$0].health>0 && Self.segmentDistance(enemies[$0].position,old,c.position)<=c.radius+enemies[$0].radius }.min { (enemies[$0].position-old).length < (enemies[$1].position-old).length }
                if let hit {
                    enemies[hit].health-=c.damage;enemies[hit].hitUntil=now+0.12
                    if c.skillID == "fireball" && c.level==5 {
                        let at=enemies[hit].position
                        for j in grid.query(from:at,to:at,margin:60) where (enemies[j].position-at).length<42+enemies[j].radius { enemies[j].health-=c.damage*0.7 }
                        state.feedback.append(.init(id:identifier(),skillID:"fireball-impact",position:at,born:now))
                    }
                    c.age=c.duration
                }
            } else if c.profile == .orbit {
                c.position=player;c.age=now;c.clipID="orbit-swords-lv\(rank(.effect("orbit-swords")))"
                let swordRank=rank(.effect("orbit-swords"))
                if now>=c.nextPulse { c.hitIDs=[];c.nextPulse=now+0.22 }
                for blade in 0..<swordRank {
                    let a = -Double.pi/2+now*2*Double.pi/2.6+Double(blade)*2*Double.pi/Double(swordRank)
                    let dir=SurvivorVector(x:cos(a),y:sin(a))
                    let start=player+dir*70,end=player+dir*104
                    for j in grid.query(from:start,to:end,margin:40) where enemies[j].health>0 && !c.hitIDs.contains(enemies[j].id) {
                        if Self.segmentDistance(enemies[j].position,start,end)<enemies[j].radius+5 { enemies[j].health-=SurvivorLocalSkills.baseDamage("orbit-swords",level:swordRank)*damageMultiplier;enemies[j].hitUntil=now+0.1;c.hitIDs.insert(enemies[j].id) }
                    }
                    if swordRank==5 {
                        let fired=2.12+Double(blade)*0.04
                        let age=(now-fired+0.13).truncatingRemainder(dividingBy:2.6)
                        let flightAge=(age<0 ? age+2.6:age)-0.13
                        if flightAge>=0 && flightAge<0.5 {
                            let angle = -Double.pi/2+fired*2*Double.pi/2.6+Double(blade)*2*Double.pi/5
                            let forward=SurvivorVector(x:cos(angle),y:sin(angle))
                            let point=player+forward*(106+54*min(1,flightAge/0.34))
                            for j in grid.query(from:point,to:point,margin:50) where enemies[j].health>0 && !c.hitIDs.contains(enemies[j].id) {
                                if (enemies[j].position-point).length<24+enemies[j].radius { enemies[j].health-=SurvivorLocalSkills.baseDamage("orbit-swords",level:swordRank)*damageMultiplier;enemies[j].hitUntil=now+0.1;c.hitIDs.insert(enemies[j].id) }
                            }
                        }
                    }
                }
            } else {
                var hits:[(Int,Double,SurvivorVector,Double,Double,Double)]=[]
                let l=c.level
                switch c.skillID {
                case "lightning": hits=[(0,0.5,.zero,12,1,1)]
                case "lightning-explosion":hits=[(0,0.42,.zero,84,0.34,1)]
                case "earth-spikes":
                    for i in 0..<l {
                        let p=SurvivorVector(x:(Double(i)-Double(l-1)/2)*Double(40+l*4),y:0)
                        hits.append((i,0.35+Double(i)*0.105,p,Double(22+l*3)*0.5,0.5,1))
                        if l==5 { hits.append((10+i,1.7+Double(i)*0.055,p,38,0.66,0.8)) }
                    }
                case "stone-fist":
                    if l==5 { hits=[(0,0.47,.init(x:-62,y:0),38,0.5,1),(1,0.63,.init(x:62,y:0),38,0.5,1),(2,0.67,.zero,142,0.23,0.6)] }
                    else { hits=[(0,0.47,.zero,46*[0.55,0.7,0.85,1][l-1],0.5,1)] }
                case "boulder":
                    hits=[(0,0.82,.zero,54*[0.58,0.74,0.9,1.06,1.13][l-1],0.35,1)]
                    if l==5 { hits += [(1,1.05,.init(x:-98,y:0),34,0.35,0.65),(2,1.25,.init(x:98,y:0),34,0.35,0.65),(3,1.3,.zero,161,0.23,0.6)] }
                case "quicksand":
                    let scale=[0.5,0.65,0.8,0.95,1.1][l-1]
                    for pulse in 0..<6 { hits.append((pulse,1.02+Double(pulse)*0.25,.zero,100*scale,0.32,0.5)) }
                    if l==5 { hits.append((10,2.15,.zero,112,0.32,1.8)) }
                    if c.age>=0.45 && c.age<2.5 {
                        for j in grid.query(from:c.position,to:c.position,margin:120) where (enemies[j].position-c.position).length<100*scale {
                            enemies[j].slowUntil=now+0.3
                            enemies[j].position=enemies[j].position+(c.position-enemies[j].position).normalized*(delta*28)
                        }
                    }
                default:break
                }
                for (event,t,offset,r,sy,multiplier) in hits where c.age>=t && !(c.events ?? []).contains(event) {
                    let at=c.position+offset
                    for j in grid.query(from:at,to:at,margin:r+45) where enemies[j].health>0 {
                        let d=enemies[j].position-at
                        if pow(d.x/(r+enemies[j].radius),2)+pow(d.y/(r*sy+enemies[j].radius),2)<=1 { enemies[j].health-=c.damage*multiplier;enemies[j].hitUntil=now+0.12 }
                    }
                    if c.events==nil {c.events=[]};c.events?.insert(event)
                }
            }
            state.casts[index]=c
        }
        state.casts.removeAll{$0.age >= $0.duration}
        if state.feedback.count>12 {state.feedback.removeFirst(state.feedback.count-12)}
        pixelFX=state
    }

    fileprivate mutating func advanceLocalMonsters(_ delta:Double) {
        let now=clock.elapsed
        for i in enemies.indices where enemies[i].health>0 {
            guard let variant=enemies[i].variant,now >= (enemies[i].nextAttack ?? now+1) else {continue}
            enemies[i].nextAttack=now+(enemies[i].kind == .boss || variant.hasSuffix("group02-elites-boss-R2C1") ? 4.016667:3.5)
            if enemies[i].kind == .boss {
                let at=enemies[i].position,dir=SurvivorVector(x:enemies[i].facingLeft ? -1:1,y:0)
                if Self.segmentDistance(player,at+dir*18,at+dir*96)<34 {takeDamage(22)}
            } else if variant.contains("group01") && variant.contains("R3C") {
                let at=enemies[i].position
                for j in enemies.indices where enemies[j].health>0 && (enemies[j].position-at).length<150 {enemies[j].health=min(enemies[j].maximumHealth,enemies[j].health+8)}
            } else if variant.contains("R4C") || variant.hasSuffix("group02-elites-boss-R2C1") {
                let at=enemies[i].position
                if (player-at).length<600 {
                    let shot=SurvivorMonsterShot(id:identifier(),position:at,velocity:(player-at).normalized*210,remaining:3,damage:8)
                    if monsterShots==nil {monsterShots=[]};if (monsterShots?.count ?? 0)<60 {monsterShots?.append(shot)}
                }
            }
        }
        guard var shots=monsterShots else {return}
        for i in shots.indices {
            let old=shots[i].position;shots[i].position=old+shots[i].velocity*delta;shots[i].remaining-=delta
            if Self.segmentDistance(player,old,shots[i].position)<18 {takeDamage(shots[i].damage);shots[i].remaining=0}
        }
        shots.removeAll{$0.remaining<=0};monsterShots=shots
    }
}
