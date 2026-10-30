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
    struct StreamingReply: Equatable {
        let characterID: String
        var text: String
    }
    @Published private(set) var streaming: [UUID: StreamingReply] = [:]
    private let file: ChatHistoryFile
    private let provider: any ChatReplyProvider
    let media: ChatMediaFiles
    var appToolHandler: ChatAppToolHandler?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]

    init(characters: [CompanionCharacter], file: ChatHistoryFile = .standard,
         provider: any ChatReplyProvider = DeepSeekChatReplyProvider(secrets: MissingAISecret())) {
        self.characters = characters
        self.file = file
        self.media = ChatMediaFiles(historyURL: file.url)
        self.provider = provider
        reload()
    }

    var conversations: [ChatConversation] {
        history.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var availableIDs: Set<String> { Set(characters.map(\.id)) }
    func conversation(_ id: UUID) -> ChatConversation? { history.conversations.first { $0.id == id } }
    func character(_ id: String?) -> CompanionCharacter? { characters.first { $0.id == id } }
    var configuration: AIChatPreferences { history.configuration ?? AIChatPreferences() }

    /// A home-screen tap is an ephemeral line, not a new saved chat conversation.
    func homeGreeting(for character: CompanionCharacter) async throws -> String {
        guard ready else { throw ChatError.invalidHistory }
        let request = HomeGreeting.request(character: character, configuration: configuration)
        let answer = try await provider.reply(to: request)
        try Task.checkCancellation()
        return try HomeGreeting.text(answer)
    }

    @discardableResult
    func saveConfiguration(_ configuration: AIChatPreferences) -> Bool {
        change { $0.configuration = configuration }
    }

    func exportBackup() throws -> Data {
        guard ready else { throw ChatError.invalidHistory }
        guard replyingIDs.isEmpty else { throw AIChatError.busy }
        var files: [String: Data] = [:]
        var total = 0
        for asset in history.mediaAssets {
            let bytes = try media.data(for: asset); total += bytes.count
            guard total <= ChatBackup.maximumSize * 3 / 4 else { throw AIChatError.backupTooLarge }
            files[asset.filename] = bytes
        }
        let data = try JSONEncoder().encode(ChatBackup(history: history, media: files))
        guard data.count <= ChatBackup.maximumSize else { throw AIChatError.backupTooLarge }
        return data
    }

    @discardableResult
    func importBackup(_ data: Data) -> Bool {
        guard replyingIDs.isEmpty else { error = AIChatError.busy.localizedDescription; return false }
        do {
            let backup = try ChatBackup.decode(data)
            for bytes in backup.media?.values ?? Dictionary<String, Data>().values { try media.store(bytes) }
            var restored = backup.history
            restored.recoverInterruptedReplies()
            try file.save(restored)
            history = restored; ready = true; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func stop(_ id: UUID) { tasks[id]?.cancel() }

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
        guard change({ message = try $0.enqueue(text, in: id, availableIDs: availableIDs, attachments: conversation(id)?.draftAttachments ?? []) }), let message else { return false }
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
            generations[id] = nil
            replyingIDs.remove(id)
            streaming[id] = nil
        }
    }

    func clear(_ id: UUID) -> Bool {
        guard !replyingIDs.contains(id) else { error = ChatError.busy.localizedDescription; return false }
        return change { value in
            guard let i = value.conversations.firstIndex(where: { $0.id == id }) else { throw ChatError.missingConversation }
            value.conversations[i].messages = []
            value.conversations[i].draft = ""
            value.conversations[i].draftAttachments = nil
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
        let preferences = configuration
        let generation = UUID()
        generations[id] = generation
        replyingIDs.insert(id)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if generations[id] == generation {
                    tasks[id] = nil; generations[id] = nil; replyingIDs.remove(id); streaming[id] = nil
                }
            }
            do {
                guard let chat = conversation(id), let turnIndex = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }
                let message = chat.messages[turnIndex]
                let members = message.replyCharacterIDs.compactMap { self.character($0) }
                let allowedTurns = Set(chat.messages.prefix(through: turnIndex).filter(\.isUser).map(\.id))
                for recipient in chat.missingReplies(to: message) {
                    try Task.checkCancellation()
                    guard let character = character(recipient) else { throw ChatError.unavailableCharacter }
                    let turnHistory = (conversation(id)?.messages ?? []).filter {
                        $0.isUser ? allowedTurns.contains($0.id) : $0.replyToID.map(allowedTurns.contains) == true
                    }
                    var request = ChatReplyRequest(conversationID: id, kind: chat.kind, groupName: chat.name,
                        members: members, character: character, userMessage: message, history: turnHistory,
                        profile: preferences.profile(for: character), userProfile: preferences.user)
                    request.stickers = (history.stickers ?? []).filter { $0.characterID == recipient }
                    // Only the selected context and four most recent images are sent to vision.
                    let prior = Array(turnHistory.filter { $0.isUser && $0.id != messageID && $0.delivery == .sent }
                        .suffix(request.profile?.contextRounds ?? 10)) + [message]
                    var remaining = 4
                    for turn in prior.reversed() {
                        let images = (turn.attachments ?? []).filter { $0.kind == .image }
                        for item in images.prefix(remaining) { request.imageURLs[turn.id, default: []].append(try media.visionURL(for: item.asset)) }
                        remaining -= min(remaining, images.count)
                    }
                    streaming[id] = StreamingReply(characterID: recipient, text: "")
                    let text = try await provider.reply(to: request, onPartial: { [weak self] text in
                        await self?.updatePartial(text, in: id, characterID: recipient, generation: generation)
                    }, onTool: { [weak self] call in
                        guard let self else { throw CancellationError() }
                        return try await self.executeTool(call, in: id, messageID: messageID, characterID: recipient, generation: generation)
                    }).trimmingCharacters(in: .whitespacesAndNewlines)
                    try Task.checkCancellation()
                    guard !text.isEmpty || !toolStickers(in: id, messageID: messageID, characterID: recipient).isEmpty else { throw ChatError.emptyReply }
                    guard change({ value in
                        guard let i = value.conversations.firstIndex(where: { $0.id == id }) else { throw ChatError.missingConversation }
                        value.conversations[i].messages.removeAll { $0.replyToID == messageID && $0.characterID == recipient && $0.interrupted == true }
                        var reply = ChatMessage.reply(text, character: character, to: messageID)
                        reply.attachments = self.toolStickers(in: id, messageID: messageID, characterID: recipient)
                        value.conversations[i].messages.append(reply)
                        value.conversations[i].updatedAt = .now
                    }) else {
                        setDelivery(.failed, in: id, messageID: messageID)
                        return
                    }
                    streaming[id] = nil
                }
                setDelivery(.sent, in: id, messageID: messageID)
            } catch is CancellationError {
                if generations[id] == generation, conversation(id) != nil { preservePartial(in: id, messageID: messageID); setDelivery(.failed, in: id, messageID: messageID) }
            } catch {
                if generations[id] == generation, conversation(id) != nil {
                    preservePartial(in: id, messageID: messageID)
                    setDelivery(.failed, in: id, messageID: messageID)
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func stickers(for characterID: String) -> [CharacterSticker] { (history.stickers ?? []).filter { $0.characterID == characterID } }

    @discardableResult
    func addSticker(data: Data, characterID: String, name: String, meaning: String) -> Bool {
        do {
            guard availableIDs.contains(characterID), stickers(for: characterID).count < 100 else { throw ChatMediaError.limit }
            let asset = try media.store(data)
            let sticker = CharacterSticker(id: UUID(), characterID: characterID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), meaning: meaning, asset: asset)
            try sticker.validate()
            return change { $0.stickers = ($0.stickers ?? []) + [sticker] }
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeSticker(_ id: UUID) { change { $0.stickers?.removeAll { $0.id == id } } }
    func editSticker(_ id: UUID, name: String, meaning: String, data: Data? = nil) -> Bool {
        do {
            let replacement = try data.map { try media.store($0) }
            return change { value in
                guard let i = value.stickers?.firstIndex(where: { $0.id == id }), let old = value.stickers?[i] else { throw ChatMediaError.missing }
                value.stickers?[i] = CharacterSticker(id: old.id, characterID: old.characterID,
                    name: name, meaning: meaning, asset: replacement ?? old.asset)
            }
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult
    func attach(data: Data, in id: UUID) -> Bool {
        do {
            guard (conversation(id)?.draftAttachments ?? []).count < 4 else { throw ChatMediaError.limit }
            let asset = try media.store(data)
            return attach(.init(id: UUID(), kind: .image, asset: asset), in: id)
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult
    func attach(_ item: ChatAttachment, in id: UUID) -> Bool {
        change { value in
            guard !replyingIDs.contains(id), let i = value.conversations.firstIndex(where: { $0.id == id }) else { throw ChatError.busy }
            let items = value.conversations[i].draftAttachments ?? []
            guard items.count < 4 else { throw ChatMediaError.limit }
            value.conversations[i].draftAttachments = items + [item]
        }
    }
    func detach(_ attachmentID: UUID, in id: UUID) {
        change { value in
            guard let i = value.conversations.firstIndex(where: { $0.id == id }) else { return }
            value.conversations[i].draftAttachments?.removeAll { $0.id == attachmentID }
        }
    }
    private func toolStickers(in id: UUID, messageID: UUID, characterID: String) -> [ChatAttachment] {
        (conversation(id)?.messages.first(where: { $0.id == messageID })?.toolReceipts ?? []).filter { $0.characterID == characterID }
            .compactMap { $0.sticker }.prefix(1).map { .init(id: $0.id, kind: .sticker, asset: $0.asset, sticker: $0) }
    }
    private func executeTool(_ call: ChatToolCall, in id: UUID, messageID: UUID, characterID: String, generation: UUID) async throws -> String {
        try Task.checkCancellation()
        guard generations[id] == generation, let character = character(characterID),
              let message = conversation(id)?.messages.first(where: { $0.id == messageID }), message.isUser else { throw CancellationError() }
        let args = try call.arguments()
        let profile = configuration.profile(for: character)
        let isSticker = call.function.name == "send_sticker"
        guard isSticker ? profile.automaticStickers == true : profile.appControl == true else { return "未执行：该角色权限已关闭。" }
        if call.function.name == "app_state" {
            guard let appToolHandler else { return "App 操作暂不可用。" }
            return try await appToolHandler(characterID, call, args)
        }
        let fingerprint = try call.fingerprint(characterID: characterID)
        if let previous = message.toolReceipts?.first(where: { $0.fingerprint == fingerprint }) {
            return previous.result ?? "此前这项操作可能已经执行，结果尚未确认；请先查看 App 当前状态，不要重复执行。"
        }
        guard (message.toolReceipts ?? []).count < 32 else { return "本轮操作已达上限。" }
        var receipt = ChatToolReceipt(fingerprint: fingerprint, characterID: characterID, name: call.function.name)
        if isSticker {
            guard toolStickers(in: id, messageID: messageID, characterID: characterID).isEmpty else { return "本轮已经发送过一个表情。" }
            guard let stickerID = UUID(uuidString: args["sticker_id"] ?? ""),
                  let sticker = stickers(for: characterID).first(where: { $0.id == stickerID }) else { return "表情不存在或不属于你。" }
            _ = try media.data(for: sticker.asset)
            receipt.sticker = sticker; receipt.result = "已发送表情：" + sticker.name
        }
        func save(_ receipt: ChatToolReceipt) -> Bool {
            change { value in
                guard let i = value.conversations.firstIndex(where: { $0.id == id }),
                      let j = value.conversations[i].messages.firstIndex(where: { $0.id == messageID }) else { throw ChatError.missingConversation }
                var receipts = value.conversations[i].messages[j].toolReceipts ?? []
                receipts.removeAll { $0.fingerprint == receipt.fingerprint }; receipts.append(receipt)
                value.conversations[i].messages[j].toolReceipts = receipts
            }
        }
        // Durable intent before side effects: a retry cannot silently execute the same write twice.
        guard save(receipt) else { throw ChatError.invalidHistory }
        if isSticker { return receipt.result! }
        guard let appToolHandler else { receipt.result = "App 操作暂不可用。"; _ = save(receipt); return receipt.result! }
        do { receipt.result = try await appToolHandler(characterID, call, args) }
        catch is CancellationError { throw CancellationError() }
        catch { receipt.result = "操作未完成，请在 App 中检查系统权限或当前状态。" }
        guard save(receipt) else { throw ChatError.invalidHistory }
        return receipt.result!
    }

    private func updatePartial(_ text: String, in id: UUID, characterID: String, generation: UUID) {
        guard conversation(id) != nil, generations[id] == generation else { return }
        streaming[id] = StreamingReply(characterID: characterID, text: text)
    }

    private func preservePartial(in id: UUID, messageID: UUID) {
        guard let partial = streaming[id],
              (!partial.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !toolStickers(in: id, messageID: messageID, characterID: partial.characterID).isEmpty),
              let character = character(partial.characterID) else { return }
        change { value in
            guard let i = value.conversations.firstIndex(where: { $0.id == id }) else { return }
            value.conversations[i].messages.removeAll { $0.replyToID == messageID && $0.characterID == character.id && $0.interrupted == true }
            var reply = ChatMessage.reply(partial.text, character: character, to: messageID)
            reply.interrupted = true
            reply.attachments = toolStickers(in: id, messageID: messageID, characterID: partial.characterID)
            value.conversations[i].messages.append(reply)
        }
    }
}
#endif
