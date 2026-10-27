import Foundation
#if canImport(Combine)
import Combine

@MainActor
final class ChatStore: ObservableObject {
    let characters: [CompanionCharacter]
    @Published private(set) var history = ChatHistory()
    @Published private(set) var replyingIDs = Set<UUID>()
    @Published private(set) var ready = false
    @Published var error: String?
    private let file: ChatHistoryFile
    private let provider: any ChatReplyProvider
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(characters: [CompanionCharacter], file: ChatHistoryFile = .standard,
         provider: any ChatReplyProvider = TestChatReplyProvider()) {
        self.characters = characters
        self.file = file
        self.provider = provider
        reload()
    }

    var conversations: [ChatConversation] {
        history.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var availableIDs: Set<String> { Set(characters.map(\.id)) }
    func conversation(_ id: UUID) -> ChatConversation? { history.conversations.first { $0.id == id } }
    func character(_ id: String?) -> CompanionCharacter? { characters.first { $0.id == id } }

    func reload() {
        guard tasks.isEmpty else { return }
        do {
            var loaded = try file.load()
            loaded.recoverInterruptedReplies()
            history = loaded
            ready = true
        } catch { ready = false; self.error = error.localizedDescription }
    }

    @discardableResult
    private func change(_ update: (inout ChatHistory) throws -> Void) -> Bool {
        guard ready else { error = ChatError.invalidHistory.localizedDescription; return false }
        do {
            var next = history
            try update(&next)
            try file.save(next)
            history = next
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func create(kind: ChatKind, name: String = "", characterIDs: [String]) -> UUID? {
        var id: UUID?
        return change { id = try $0.create(kind: kind, name: name, characterIDs: characterIDs, availableIDs: availableIDs) } ? id : nil
    }

    func editGroup(_ id: UUID, name: String, characterIDs: [String]) -> Bool {
        guard !replyingIDs.contains(id) else { error = ChatError.busy.localizedDescription; return false }
        return change { try $0.editGroup(id, name: name, characterIDs: characterIDs, availableIDs: availableIDs) }
    }

    func setDraft(_ text: String, in id: UUID) {
        guard conversation(id)?.draft != text else { return }
        change { value in
            guard let i = value.conversations.firstIndex(where: { $0.id == id }) else { return }
            value.conversations[i].draft = text
        }
    }

    func send(_ text: String, in id: UUID) -> Bool {
        guard !replyingIDs.contains(id) else { return false }
        var message: ChatMessage?
        guard change({ message = try $0.enqueue(text, in: id, availableIDs: availableIDs) }), let message else { return false }
        beginReply(in: id, to: message.id)
        return true
    }

    func retry(in id: UUID, messageID: UUID) {
        guard !replyingIDs.contains(id), let chat = conversation(id),
              let message = chat.messages.first(where: { $0.id == messageID && $0.isUser && $0.delivery == .failed }) else { return }
        guard chat.missingReplies(to: message).allSatisfy(availableIDs.contains) else {
            error = ChatError.unavailableCharacter.localizedDescription; return
        }
        guard setDelivery(.waiting, in: id, messageID: messageID) else { return }
        beginReply(in: id, to: messageID)
    }

    func delete(_ id: UUID) {
        // Commit removal first, then cancel; a failed disk write leaves the conversation usable.
        if change({ $0.conversations.removeAll { $0.id == id } }) {
            tasks[id]?.cancel()
            tasks[id] = nil
            replyingIDs.remove(id)
        }
    }

    func clear(_ id: UUID) -> Bool {
        guard !replyingIDs.contains(id) else { error = ChatError.busy.localizedDescription; return false }
        return change { value in
            guard let i = value.conversations.firstIndex(where: { $0.id == id }) else { throw ChatError.missingConversation }
            value.conversations[i].messages = []
            value.conversations[i].draft = ""
        }
    }

    @discardableResult
    private func setDelivery(_ delivery: ChatDelivery, in id: UUID, messageID: UUID) -> Bool {
        let saved = change { value in
            guard let i = value.conversations.firstIndex(where: { $0.id == id }),
                  let j = value.conversations[i].messages.firstIndex(where: { $0.id == messageID }) else { throw ChatError.missingConversation }
            value.conversations[i].messages[j].delivery = delivery
        }
        // Disk errors must not leave an inactive turn permanently waiting in the UI.
        // The next launch derives the same final/retryable state from persisted replies.
        if !saved, delivery != .waiting,
           let i = history.conversations.firstIndex(where: { $0.id == id }),
           let j = history.conversations[i].messages.firstIndex(where: { $0.id == messageID }) {
            history.conversations[i].messages[j].delivery = delivery
        }
        return saved
    }

    private func beginReply(in id: UUID, to messageID: UUID) {
        replyingIDs.insert(id)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { tasks[id] = nil; replyingIDs.remove(id) }
            do {
                guard let chat = conversation(id), let turnIndex = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }
                let message = chat.messages[turnIndex]
                let members = message.replyCharacterIDs.compactMap { self.character($0) }
                let turnHistory = Array(chat.messages.prefix(through: turnIndex))
                for recipient in chat.missingReplies(to: message) {
                    try Task.checkCancellation()
                    guard let character = character(recipient) else { throw ChatError.unavailableCharacter }
                    let request = ChatReplyRequest(conversationID: id, kind: chat.kind, groupName: chat.name,
                                                   members: members, character: character, userMessage: message, history: turnHistory)
                    let text = try await provider.reply(to: request).trimmingCharacters(in: .whitespacesAndNewlines)
                    try Task.checkCancellation()
                    guard !text.isEmpty else { throw ChatError.emptyReply }
                    guard change({ value in
                        guard let i = value.conversations.firstIndex(where: { $0.id == id }) else { throw ChatError.missingConversation }
                        value.conversations[i].messages.append(.reply(text, character: character, to: messageID))
                        value.conversations[i].updatedAt = .now
                    }) else {
                        setDelivery(.failed, in: id, messageID: messageID)
                        return
                    }
                }
                setDelivery(.sent, in: id, messageID: messageID)
            } catch is CancellationError {
                if conversation(id) != nil { setDelivery(.failed, in: id, messageID: messageID) }
            } catch {
                if conversation(id) != nil {
                    setDelivery(.failed, in: id, messageID: messageID)
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
#endif
