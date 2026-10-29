import Foundation

struct AICharacterProfile: Codable, Equatable, Sendable {
    var model = "deepseek-flash"
    var thinking = false
    var contextRounds = 10
    var maxOutputTokens = 4096
    var background = ""
    var personality = ""
    var speakingStyle = ""
    var interests = ""
    var relationship = ""
    var callsUser = ""
    var additionalInstructions = ""

    static func standard(for character: CompanionCharacter) -> Self {
        var profile = Self()
        profile.background = "你是\(character.name)，\(character.subtitle)。\(character.introduction)"
        profile.personality = character.id == "dafeiyu" ? "活泼、亲切，喜欢自然地开玩笑，也会认真倾听。" : "温柔、耐心，表达自然，尊重对方的感受。"
        profile.speakingStyle = "像日常聊天一样交流，通常简洁回应，需要解释时再展开。"
        return profile
    }
    func validate() throws {
        let modelBytes = Array(model.utf8)
        guard !modelBytes.isEmpty, modelBytes.count <= 120,
              modelBytes.allSatisfy({ (33...126).contains($0) }),
              (0...100).contains(contextRounds), (128...32768).contains(maxOutputTokens),
              [background, personality, speakingStyle, interests, relationship, callsUser, additionalInstructions].allSatisfy({ $0.count <= 4000 }),
              [background, personality, speakingStyle, interests, relationship, callsUser, additionalInstructions].reduce(0, { $0 + $1.count }) <= 16000 else { throw AIChatError.invalidConfiguration }
    }
}

struct AIUserProfile: Codable, Equatable, Sendable {
    var nickname = ""
    var information = ""
    var shareWithCharacters = true
}

struct AIChatPreferences: Codable, Equatable, Sendable {
    var characters: [String: AICharacterProfile] = [:]
    var user = AIUserProfile()
    func profile(for character: CompanionCharacter) -> AICharacterProfile {
        characters[character.id] ?? .standard(for: character)
    }
    func validate() throws {
        guard characters.count <= 100, user.nickname.count <= 100, user.information.count <= 4000,
              characters.keys.allSatisfy({ !$0.isEmpty && $0.count <= 120 }) else { throw AIChatError.invalidConfiguration }
        for profile in characters.values { try profile.validate() }
    }
}

enum AIChatError: LocalizedError {
    case missingKey, invalidKey, invalidConfiguration, unsupportedModel, invalidResponse
    case http(Int), network, timeout, truncated, interrupted, backupVersion, busy
    var errorDescription: String? {
        switch self {
        case .missingKey: return "请先在角色详情的「AI 与人格」中配置 DeepSeek 密钥。"
        case .invalidKey: return "密钥格式不正确，请检查是否有空格或换行。"
        case .invalidConfiguration: return "配置超出允许范围，请检查模型、人设长度和上下文设置。"
        case .unsupportedModel: return "该模型暂不支持当前设置，请重新选择模型。"
        case .invalidResponse: return "服务返回的数据无法读取，请重试。"
        case .http(let code):
            switch code {
            case 401, 403: return "DeepSeek 密钥无效或没有访问权限，请检查配置。"
            case 402: return "DeepSeek 账户余额不足，请在开放平台查看。"
            case 404: return "模型或接口不存在，请刷新模型列表后重试。"
            case 429: return "请求过于频繁，请稍后重试。"
            case 500...599: return "DeepSeek 服务暂时不可用，请稍后重试。"
            default: return "DeepSeek 拒绝了请求（\(code)），请检查模型与参数。"
            }
        case .network: return "网络连接中断，请检查网络后重试。"
        case .timeout: return "等待回复超时，请稍后重试。"
        case .truncated: return "回复达到输出上限，已保留收到的内容。可提高输出上限后重试。"
        case .interrupted: return "回复未完整接收，已保留收到的内容，可以重试。"
        case .backupVersion: return "备份格式或版本不支持，原有记录未修改。"
        case .busy: return "请先停止当前回复，再进行此操作。"
        }
    }
}

struct AIChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

enum AIChatContext {
    static func messages(for request: ChatReplyRequest) throws -> [AIChatMessage] {
        let profile = request.profile ?? .standard(for: request.character)
        try profile.validate()
        let parts = [("身份背景", profile.background), ("性格", profile.personality),
                     ("说话习惯", profile.speakingStyle), ("喜好", profile.interests),
                     ("与用户的关系", profile.relationship), ("称呼用户", profile.callsUser),
                     ("补充人设", profile.additionalInstructions)]
        var system = "你正在以\(request.character.name)的角色参与聊天。只以自己的身份回答，不代替用户或其他角色发言。\n"
        system += parts.filter { !$0.1.isEmpty }.map { "\($0.0)：\($0.1)" }.joined(separator: "\n")
        if let user = request.userProfile, user.shareWithCharacters {
            system += "\n用户主动提供的资料：昵称「\(user.nickname)」。\(user.information)"
        }
        if request.kind == .group {
            system += "\n你在群聊「\(request.groupName)」中，成员有：\(request.members.map(\.name).joined(separator: "、"))。标有其他成员名字的消息是他们说的话。"
        }
        let previous = request.history.filter { $0.isUser && $0.id != request.userMessage.id && $0.delivery == .sent }
        let selected = profile.contextRounds == 0 ? [] : Array(previous.suffix(profile.contextRounds))
        var result = [AIChatMessage(role: "system", content: system)]
        func appendReplies(to parent: UUID) {
            for reply in request.history where reply.replyToID == parent && reply.interrupted != true {
                if reply.characterID == request.character.id {
                    result.append(.init(role: "assistant", content: reply.text))
                } else if request.kind == .group {
                    result.append(.init(role: "user", content: "[\(reply.senderName)] \(reply.text)"))
                }
            }
        }
        for turn in selected {
            result.append(.init(role: "user", content: turn.text)); appendReplies(to: turn.id)
        }
        result.append(.init(role: "user", content: request.userMessage.text))
        if request.kind == .group { appendReplies(to: request.userMessage.id) }
        return result
    }
}

struct ChatBackup: Codable {
    let format: String
    let version: Int
    let createdAt: Date
    let history: ChatHistory
    init(history: ChatHistory) throws {
        try history.validate()
        self.format = "mAIverse.chat.backup"; self.version = 1; self.createdAt = .now; self.history = history
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 20 * 1024 * 1024 else { throw AIChatError.backupVersion }
        let value: Self
        do { value = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw AIChatError.backupVersion }
        guard value.format == "mAIverse.chat.backup", value.version == 1 else { throw AIChatError.backupVersion }
        try value.history.validate()
        return value
    }
}
