import Foundation

enum SurvivorRuleError: Error { case invalidConfiguration, invalidDelta }

/// Pure rules for the proposed survivor game. No rendering or App entry yet.
struct SurvivorRunConfiguration: Codable, Equatable, Sendable {
    struct Stage: Codable, Equatable, Sendable {
        let id: String
        let startsAt: TimeInterval
        let endsAt: TimeInterval
        let spawnInterval: TimeInterval
        let enemyLimit: Int
    }
    let duration: TimeInterval
    let stages: [Stage]

    /// Spawn values are initial tuning candidates, not verified device budgets.
    static let standard = Self(duration: 20 * 60, stages: [
        .init(id: "opening", startsAt: 0, endsAt: 180, spawnInterval: 2, enemyLimit: 30),
        .init(id: "growth", startsAt: 180, endsAt: 480, spawnInterval: 1.4, enemyLimit: 60),
        .init(id: "build", startsAt: 480, endsAt: 840, spawnInterval: 1, enemyLimit: 80),
        .init(id: "pressure", startsAt: 840, endsAt: 1080, spawnInterval: 0.75, enemyLimit: 100),
        .init(id: "finale", startsAt: 1080, endsAt: 1200, spawnInterval: 1, enemyLimit: 100)
    ])

    func validate() throws {
        guard duration.isFinite, duration > 0, !stages.isEmpty,
              Set(stages.map(\.id)).count == stages.count,
              stages.first?.startsAt == 0, stages.last?.endsAt == duration else {
            throw SurvivorRuleError.invalidConfiguration
        }
        var previousEnd: TimeInterval = 0
        for stage in stages {
            guard !stage.id.isEmpty, stage.startsAt.isFinite, stage.endsAt.isFinite,
                  stage.startsAt == previousEnd, stage.endsAt > stage.startsAt,
                  stage.spawnInterval.isFinite, stage.spawnInterval > 0, stage.enemyLimit > 0 else {
                throw SurvivorRuleError.invalidConfiguration
            }
            previousEnd = stage.endsAt
        }
    }

    func stage(at activeTime: TimeInterval) -> Stage? {
        guard activeTime.isFinite, activeTime >= 0, activeTime < duration else { return nil }
        return stages.first { $0.startsAt <= activeTime && activeTime < $0.endsAt }
    }
}

/// Receives active simulation deltas, never wall-clock dates. The renderer must
/// reset its previous frame timestamp when resuming after a background pause.
struct SurvivorRunClock: Codable, Equatable, Sendable {
    enum PauseReason: String, Codable, Hashable, Sendable { case upgrade, menu, background }
    let duration: TimeInterval
    private(set) var elapsed: TimeInterval = 0
    private(set) var started = false
    private(set) var pauseReasons = Set<PauseReason>()

    var finished: Bool { elapsed == duration }
    var running: Bool { started && !finished && pauseReasons.isEmpty }
    var remaining: TimeInterval { max(0, duration - elapsed) }

    init(duration: TimeInterval = SurvivorRunConfiguration.standard.duration) throws {
        guard duration.isFinite, duration > 0 else { throw SurvivorRuleError.invalidConfiguration }
        self.duration = duration
    }

    mutating func start() { started = true }
    mutating func pause(_ reason: PauseReason) { pauseReasons.insert(reason) }
    mutating func resume(_ reason: PauseReason) { pauseReasons.remove(reason) }

    mutating func advance(by delta: TimeInterval) throws {
        guard delta.isFinite, delta >= 0 else { throw SurvivorRuleError.invalidDelta }
        guard running else { return }
        // Clamp at the endpoint, including sub-microsecond fixed-step rounding.
        let next = min(duration, elapsed + min(delta, remaining))
        elapsed = duration - next <= 0.0000001 ? duration : next
    }

    private enum CodingKeys: String, CodingKey { case duration, elapsed, started, pauseReasons }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let duration = try values.decode(TimeInterval.self, forKey: .duration)
        let elapsed = try values.decode(TimeInterval.self, forKey: .elapsed)
        guard duration.isFinite, duration > 0, elapsed.isFinite, elapsed >= 0, elapsed <= duration else {
            throw SurvivorRuleError.invalidConfiguration
        }
        self.duration = duration; self.elapsed = elapsed
        started = try values.decode(Bool.self, forKey: .started)
        pauseReasons = try values.decode(Set<PauseReason>.self, forKey: .pauseReasons)
        guard started || elapsed == 0 else { throw SurvivorRuleError.invalidConfiguration }
    }
}
