import Foundation

enum ChatKind: String, Codable, Sendable { case direct, group }
enum ChatDelivery: String, Codable, Sendable { case sent, waiting, failed }

struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let characterID: String?
    let senderName: String
    let text: String
    let createdAt: Date
    let replyToID: UUID?
    let replyCharacterIDs: [String]
    var delivery: ChatDelivery

    var isUser: Bool { characterID == nil }

    static func user(_ text: String, recipients: [String], now: Date = .now) -> ChatMessage {
        ChatMessage(id: UUID(), characterID: nil, senderName: "我", text: text, createdAt: now,
                    replyToID: nil, replyCharacterIDs: recipients, delivery: .waiting)
    }

    static func reply(_ text: String, character: CompanionCharacter, to messageID: UUID,
                      now: Date = .now) -> ChatMessage {
        ChatMessage(id: UUID(), characterID: character.id, senderName: character.name, text: text,
                    createdAt: now, replyToID: messageID, replyCharacterIDs: [], delivery: .sent)
    }
}

struct ChatConversation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: ChatKind
    var name: String
    var characterIDs: [String]
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage] = []
    var draft = ""

    func title(in characters: [CompanionCharacter]) -> String {
        if kind == .group { return name }
        return characters.first { $0.id == characterIDs.first }?.name
            ?? messages.last(where: { !$0.isUser })?.senderName ?? "暂不可用的角色"
    }

    func missingReplies(to message: ChatMessage) -> [String] {
        let replied = Set(messages.filter { $0.replyToID == message.id }.compactMap(\.characterID))
        return message.replyCharacterIDs.filter { !replied.contains($0) }
    }
}

enum ChatError: LocalizedError {
    case noCharacters, invalidDirect, emptyName, longName, emptyMessage, longMessage, unavailableCharacter
    case missingConversation, busy, invalidHistory, emptyReply

    var errorDescription: String? {
        switch self {
        case .noCharacters: return "请至少选择一个角色。"
        case .invalidDirect: return "单聊只能选择一个角色。"
        case .emptyName: return "请填写群组名称。"
        case .longName: return "群组名称最多 30 个字。"
        case .emptyMessage: return "请输入消息。"
        case .longMessage: return "每条消息最多 4000 个字。"
        case .unavailableCharacter: return "有角色暂不可用，请调整群成员后再发送。"
        case .missingConversation: return "这段聊天已被删除。"
        case .busy: return "请等这一轮回复结束后再操作。"
        case .invalidHistory: return "聊天记录无法读取。原文件已保留，请重试或检查备份。"
        case .emptyReply: return "角色没有返回内容，请重试。"
        }
    }
}

struct ChatHistory: Codable, Equatable, Sendable {
    var version = 1
    var conversations: [ChatConversation] = []

    mutating func create(kind: ChatKind, name: String, characterIDs: [String],
                         availableIDs: Set<String>, now: Date = .now) throws -> UUID {
        var seen = Set<String>()
        let ids = characterIDs.filter { seen.insert($0).inserted }
        try Self.validateMembers(ids, availableIDs: availableIDs)
        if kind == .direct {
            guard ids.count == 1 else { throw ChatError.invalidDirect }
            if let existing = conversations.first(where: { $0.kind == .direct && $0.characterIDs == ids }) {
                return existing.id
            }
        }
        let title = kind == .group ? try Self.groupName(name) : ""
        let conversation = ChatConversation(id: UUID(), kind: kind, name: title, characterIDs: ids,
                                            createdAt: now, updatedAt: now)
        conversations.append(conversation)
        return conversation.id
    }

    mutating func editGroup(_ id: UUID, name: String, characterIDs: [String],
                           availableIDs: Set<String>, now: Date = .now) throws {
        guard let index = conversations.firstIndex(where: { $0.id == id }),
              conversations[index].kind == .group else { throw ChatError.missingConversation }
        guard !conversations[index].messages.contains(where: { $0.delivery == .waiting }) else { throw ChatError.busy }
        var seen = Set<String>()
        let ids = characterIDs.filter { seen.insert($0).inserted }
        try Self.validateMembers(ids, availableIDs: availableIDs)
        conversations[index].name = try Self.groupName(name)
        conversations[index].characterIDs = ids
        conversations[index].updatedAt = now
    }

    mutating func enqueue(_ text: String, in id: UUID, availableIDs: Set<String>,
                          now: Date = .now) throws -> ChatMessage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatError.emptyMessage }
        guard trimmed.count <= 4000 else { throw ChatError.longMessage }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { throw ChatError.missingConversation }
        guard !conversations[index].messages.contains(where: { $0.delivery == .waiting }) else { throw ChatError.busy }
        let ids = conversations[index].characterIDs
        try Self.validateMembers(ids, availableIDs: availableIDs)
        let message = ChatMessage.user(trimmed, recipients: ids, now: now)
        conversations[index].messages.append(message)
        conversations[index].draft = ""
        conversations[index].updatedAt = now
        return message
    }

    mutating func recoverInterruptedReplies() {
        for i in conversations.indices {
            for j in conversations[i].messages.indices where conversations[i].messages[j].delivery == .waiting {
                let message = conversations[i].messages[j]
                conversations[i].messages[j].delivery = conversations[i].missingReplies(to: message).isEmpty ? .sent : .failed
            }
        }
    }

    func validate() throws {
        guard version == 1, Set(conversations.map(\.id)).count == conversations.count else { throw ChatError.invalidHistory }
        for conversation in conversations {
            let ids = conversation.characterIDs
            guard !ids.isEmpty, ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count,
                  conversation.kind != .direct || ids.count == 1,
                  Set(conversation.messages.map(\.id)).count == conversation.messages.count else { throw ChatError.invalidHistory }
            for message in conversation.messages {
                guard !message.text.isEmpty,
                      (message.isUser ? message.replyToID == nil : message.replyToID != nil),
                      message.isUser || message.delivery == .sent else { throw ChatError.invalidHistory }
            }
        }
    }

    private static func validateMembers(_ ids: [String], availableIDs: Set<String>) throws {
        guard !ids.isEmpty else { throw ChatError.noCharacters }
        guard ids.allSatisfy(availableIDs.contains) else { throw ChatError.unavailableCharacter }
    }

    private static func groupName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ChatError.emptyName }
        guard value.count <= 30 else { throw ChatError.longName }
        return value
    }
}

/// Contains a fixed turn and its history, so an API implementation can preserve role and group context.
struct ChatReplyRequest: Sendable {
    let conversationID: UUID
    let kind: ChatKind
    let groupName: String
    let members: [CompanionCharacter]
    let character: CompanionCharacter
    let userMessage: ChatMessage
    let history: [ChatMessage]
}

protocol ChatReplyProvider: Sendable {
    func reply(to request: ChatReplyRequest) async throws -> String
}

struct TestChatReplyProvider: ChatReplyProvider {
    func reply(to request: ChatReplyRequest) async throws -> String {
        try await Task.sleep(nanoseconds: 400_000_000)
        try Task.checkCancellation()
        return "聊天功能测试中"
    }
}

/// A separate, atomic JSON file; a corrupt/unsupported history is never silently overwritten.
struct ChatHistoryFile {
    let url: URL

    static var standard: ChatHistoryFile {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--chat-test-store"), args.indices.contains(flag + 1),
           let testID = UUID(uuidString: args[flag + 1]) {
            return ChatHistoryFile(url: directory.appendingPathComponent("Chat/UITests/\(testID.uuidString)/history.json"))
        }
        #endif
        return ChatHistoryFile(url: directory.appendingPathComponent("Chat/history.json"))
    }

    func load() throws -> ChatHistory {
        guard FileManager.default.fileExists(atPath: url.path) else { return ChatHistory() }
        do {
            let history = try JSONDecoder().decode(ChatHistory.self, from: Data(contentsOf: url))
            try history.validate()
            return history
        } catch { throw ChatError.invalidHistory }
    }

    func save(_ history: ChatHistory) throws {
        try history.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: url, options: .atomic)
    }
}
