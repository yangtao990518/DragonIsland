import Foundation

/// One frame per source picture. Display selection follows PTS, including holds.
struct HomeSceneAnimation: Decodable, Sendable {
    let id: String
    let characterID: String
    let title: String
    let frameCount: Int
    let frameSize: [Int]
    let durationMs: Double
    let frameNames: [String]
    let frameStartMs: [Double]
    let frameDurationsMs: [Double]

    var isValid: Bool {
        guard frameCount > 0, frameCount <= 2400, frameSize.count == 2,
              frameSize.allSatisfy({ $0 > 0 && $0 <= 4096 }),
              durationMs.isFinite, durationMs > 0, durationMs <= 20_000,
              frameNames.count == frameCount, frameStartMs.count == frameCount,
              frameDurationsMs.count == frameCount, frameStartMs.first == 0,
              Set(frameNames).count == frameCount,
              frameNames.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 } }) else { return false }
        for i in 0..<frameCount {
            guard frameStartMs[i].isFinite, frameDurationsMs[i].isFinite,
                  frameDurationsMs[i] > 0 else { return false }
            let end = i + 1 < frameCount ? frameStartMs[i + 1] : durationMs
            guard end > frameStartMs[i], abs(frameStartMs[i] + frameDurationsMs[i] - end) < 0.01 else { return false }
        }
        return true
    }

    func frameIndex(elapsed: TimeInterval) -> Int {
        guard !frameStartMs.isEmpty else { return 0 }
        let ms = max(0, elapsed * 1000)
        var low = 0, high = frameStartMs.count
        while low < high {
            let middle = (low + high) / 2
            if frameStartMs[middle] <= ms { low = middle + 1 } else { high = middle }
        }
        return max(0, min(frameCount - 1, low - 1))
    }

    static func load(bundle: Bundle = .main) -> [Self] {
        guard let url = bundle.url(forResource: "HomeScenes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return values.filter(\.isValid)
    }
}

enum HomeGreeting {
    static func text(_ answer: String) throws -> String {
        let compact = answer.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !compact.isEmpty else { throw AIChatError.invalidResponse }
        return String(compact.prefix(20))
    }

    static func request(character: CompanionCharacter, configuration: AIChatPreferences) -> ChatReplyRequest {
        var profile = configuration.profile(for: character)
        profile.contextRounds = 0
        profile.maxOutputTokens = 128
        profile.thinking = false
        profile.appControl = false
        profile.automaticStickers = false
        let message = ChatMessage.user("我轻轻点了你一下，你现在想对我说什么？请用一句不超过20个字符的中文台词回答。只给台词，不要解释、旁白或工具调用。", recipients: [character.id])
        return ChatReplyRequest(conversationID: UUID(), kind: .direct, groupName: "", members: [character],
            character: character, userMessage: message, history: [], profile: profile, userProfile: configuration.user)
    }
}
