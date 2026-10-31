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

enum SurvivorUpgrade: String, Codable, CaseIterable, Identifiable, Sendable {
    case thunder, bubble, power, haste, stride, magnet, vitality, mend
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thunder: return "紫霄雷"
        case .bubble: return "水泡术"
        case .power: return "凝神"
        case .haste: return "灵息"
        case .stride: return "踏风"
        case .magnet: return "聚灵"
        case .vitality: return "护心"
        case .mend: return "回春"
        }
    }
    var symbol: String {
        switch self {
        case .thunder: return "bolt.fill"
        case .bubble: return "bubbles.and.sparkles.fill"
        case .power: return "sparkles"
        case .haste: return "timer"
        case .stride: return "wind"
        case .magnet: return "circle.dotted.circle.fill"
        case .vitality: return "heart.fill"
        case .mend: return "cross.case.fill"
        }
    }
    var maximum: Int {
        switch self {
        case .thunder, .bubble, .power, .haste: return 5
        case .stride, .magnet, .vitality: return 3
        case .mend: return Int.max
        }
    }
    func detail(current: Int) -> String {
        switch self {
        case .thunder: return current == 0 ? "自动召唤雷阵，持续打击前方敌人" : "雷阵提升至\(current + 1)级，扩大范围并增强伤害"
        case .bubble: return "增强自动水泡；3级、5级增加一枚弹体"
        case .power: return "全部攻击伤害提高14%"
        case .haste: return "缩短水泡和雷阵的自动释放间隔"
        case .stride: return "移动速度提高10%"
        case .magnet: return "扩大经验拾取和吸引范围"
        case .vitality: return "生命上限增加20，并回复20点生命"
        case .mend: return "立即回复35点生命"
        }
    }
}

enum SurvivorEnemyKind: String, Codable, Sendable { case demon, mushroom, elite, boss }
enum SurvivorOutcome: String, Codable, Sendable { case victory, defeat }

struct SurvivorEnemy: Codable, Identifiable, Sendable {
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
    let configuration: SurvivorRunConfiguration
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
    let thunderDuration: Double
    private var random: SurvivorRandom
    private var nextID: UInt64 = 1
    private var spawnIn: Double = 0.5
    private var bubbleIn: Double = 0.2
    private var thunderIn: Double = 0.2
    private var invincibleUntil: Double = 0
    private var bossSpawned = false

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
        var remaining = delta
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
        if abs(direction.x) > 0.01 { facingLeft = direction.x < 0 }

        spawnIn -= delta
        if let stage = configuration.stage(at: clock.elapsed), spawnIn <= 0 {
            spawnIn += stage.spawnInterval
            if enemies.count < stage.enemyLimit {
                let angle = random.unit() * .pi * 2
                let distance = 430 + random.unit() * 120
                let kind: SurvivorEnemyKind = random.unit() < 0.42 ? .mushroom : .demon
                _ = spawnEnemy(at: player + .init(x: cos(angle), y: sin(angle)) * distance, kind: kind)
            }
        }
        if !bossSpawned, clock.elapsed >= configuration.duration * 0.90 {
            bossSpawned = true
            _ = spawnEnemy(at: player + .init(x: 0, y: 480), kind: .boss)
        }
        for i in enemies.indices where enemies[i].health > 0 {
            let toPlayer = player - enemies[i].position
            if abs(toPlayer.x) > 0.5 { enemies[i].facingLeft = toPlayer.x < 0 }
            enemies[i].position = enemies[i].position + toPlayer.normalized * (enemies[i].speed * delta)
        }
        let grid = SurvivorEnemyGrid(enemies)
        separateEnemies(grid)

        bubbleIn -= delta
        if bubbleIn <= 0, let target = nearestEnemy() {
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
        for enemy in enemies where enemy.health <= 0 {
            kills += 1
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
            enemies[i].position = player + SurvivorVector(x: cos(angle), y: sin(angle)) * 490
        }
        for enemy in enemies where (enemy.position - player).length <= enemy.radius + 13 {
            takeDamage(enemy.kind == .boss ? 18 : 8)
        }
        for i in drops.indices {
            let distance = (player - drops[i].position).length
            if distance <= pickupRadius { experience += drops[i].value; drops[i].value = 0 }
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
        enemies.append(.init(id: enemyID, kind: kind, position: position, health: hp, maximumHealth: hp,
                             speed: speed + min(22, clock.elapsed / 80), radius: kind == .boss ? 35 : 14))
        return enemyID
    }

    mutating func takeDamage(_ damage: Double) {
        guard clock.running, clock.elapsed >= invincibleUntil, outcome == nil, damage.isFinite, damage > 0 else { return }
        health = max(0, health - damage)
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
        let available = SurvivorUpgrade.allCases.filter {
            rank($0) < $0.maximum && ($0 != .mend || health < maximumHealth)
        }
        var options = random.shuffle(available)
        if rank(.thunder) == 0 {
            options.removeAll { $0 == .thunder }; options.insert(.thunder, at: 0)
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

private struct SurvivorEnemyGrid {
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
