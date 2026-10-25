import Foundation

enum CompanionMotion: String, Codable, Hashable {
    case walk, roll
    var title: String { self == .walk ? "走动" : "翻滚" }
}

enum DragonMood: String, Codable, Hashable, CaseIterable {
    case calm, cheerful, sleepy

    var title: String {
        switch self {
        case .calm: return "安静陪你"
        case .cheerful: return "给你打气"
        case .sleepy: return "一起放松"
        }
    }

    var symbol: String {
        switch self {
        case .calm: return "moon.stars.fill"
        case .cheerful: return "sparkles"
        case .sleepy: return "cloud.moon.fill"
        }
    }

    var message: String {
        switch self {
        case .calm: return "你忙你的，我就在这里。"
        case .cheerful: return "慢慢来，你已经往前走了一点。"
        case .sleepy: return "肩膀放松，和我一起歇一会儿。"
        }
    }

    var next: DragonMood {
        switch self {
        case .calm: return .cheerful
        case .cheerful: return .sleepy
        case .sleepy: return .calm
        }
    }
}

struct CompanionSession: Codable, Hashable {
    let startedAt: Date
    let endsAt: Date
    var mood: DragonMood
    var message: String
    var greetings: Int
    var revision: Int
    // Optional fields preserve decoding of sessions from earlier releases.
    var motion: CompanionMotion?
    var motionSequence: Int?
    var walkSteps: Int?
    var rollTurns: Int?
    var automaticMotionPlan: Int?
    var motionEpoch: Date?
    var islandSceneID: String?
    var islandScene: IslandScene { IslandScene.resolve(islandSceneID) }

    private mutating func recordMotion(_ action: CompanionMotion) {
        motion = action
        motionSequence = (motionSequence ?? 0) + 1
        if action == .walk { walkSteps = (walkSteps ?? 0) + 1 }
        else { rollTurns = (rollTurns ?? 0) + 1 }
    }

    mutating func performMotion(_ action: CompanionMotion) {
        recordMotion(action)
        message = action == .walk ? "走两步，也陪你换换心情。" : "打个滚，今天也轻松一点。"
        revision += 1
    }

    init(minutes: Int, now: Date = Date()) {
        // A finite session, well below the system's 8-hour Live Activity limit.
        let safeMinutes = min(max(minutes, 1), 120)
        startedAt = now
        endsAt = now.addingTimeInterval(TimeInterval(safeMinutes * 60))
        mood = .calm
        message = DragonMood.calm.message
        greetings = 0
        revision = 0
    }

    var timerRange: ClosedRange<Date> { startedAt...endsAt }

    func remainingSeconds(at date: Date = Date()) -> Int {
        max(0, Int(ceil(endsAt.timeIntervalSince(date))))
    }

    func hasExpired(at date: Date = Date()) -> Bool { date >= endsAt }

    mutating func greet() {
        let phrases = ["收到你的招呼啦。", "嗯？我在听。", "今天也陪你多待一会儿。", "不用着急，我们慢慢来。"]
        message = phrases[greetings % phrases.count]
        greetings += 1
        recordMotion(.walk)
        revision += 1
    }

    mutating func cycleMood() {
        mood = mood.next
        message = mood.message
        recordMotion(.roll)
        revision += 1
    }
}
