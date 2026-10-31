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
    @Published var visibleConversationID: UUID?
    @Published var requestedConversationID: UUID?
    @Published private(set) var preparingProactiveIDs = Set<UUID>()
    private let builtinStickers: [CharacterSticker]
    struct StreamingReply: Equatable {
        let characterID: String
        var text: String
    }
    @Published private(set) var streaming: [UUID: StreamingReply] = [:]
    private let file: ChatHistoryFile
    private let provider: any ChatReplyProvider
    let media: ChatMediaFiles
    let memoryFiles: CharacterMemoryFiles
    @Published private(set) var memoryRevision = 0
    @Published private(set) var preparingMemoryRoles = Set<String>()
    var appToolHandler: ChatAppToolHandler?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]

    init(characters: [CompanionCharacter], file: ChatHistoryFile = .standard,
         provider: any ChatReplyProvider = DeepSeekChatReplyProvider(secrets: MissingAISecret()),
         builtinStickers: [CharacterSticker] = BuiltinStickerCatalog.load(), mediaFiles: ChatMediaFiles? = nil) {
        self.characters = characters
        self.file = file
        self.media = mediaFiles ?? ChatMediaFiles(historyURL: file.url)
        self.memoryFiles = CharacterMemoryFiles(historyURL: file.url)
        self.provider = provider
        self.builtinStickers = builtinStickers
        reload()
    }

    var conversations: [ChatConversation] {
        history.conversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var availableIDs: Set<String> { Set(characters.map(\.id)) }
    func conversation(_ id: UUID) -> ChatConversation? { history.conversations.first { $0.id == id } }
    func character(_ id: String?) -> CompanionCharacter? { characters.first { $0.id == id } }
    var configuration: AIChatPreferences { history.configuration ?? AIChatPreferences() }
    var historyFileURL: URL { file.url }
    func memoryAutomation(for role: String) -> MemoryAutomationRole { history.memoryAutomation?.roles[role] ?? .init() }
    @discardableResult
    func setAutomaticMemory(_ enabled: Bool, for role: String) -> Bool {
        guard availableIDs.contains(role), !preparingMemoryRoles.contains(role) else { error = AIChatError.busy.localizedDescription; return false }
        return change { value in
            var automation = value.memoryAutomation ?? MemoryAutomation()
            var settings = automation.roles[role] ?? MemoryAutomationRole()
            if enabled && !settings.enabled {
                // Enabling automation never silently sends an entire old archive.
                for chat in value.conversations where chat.characterIDs.contains(role) {
                    if let last = chat.messages.last(where: { $0.isUser && $0.delivery == .sent && $0.replyCharacterIDs.contains(role) }) {
                        settings.processedThrough[chat.id.uuidString] = last.id
                    }
                }
            }
            settings.enabled = enabled; automation.roles[role] = settings; value.memoryAutomation = automation
        }
    }
    func prepareAutomaticMemories(in conversationID: UUID? = nil) async {
        for character in characters where memoryAutomation(for: character.id).enabled {
            if Task.isCancelled { return }
            guard !preparingMemoryRoles.contains(character.id), !conversations.contains(where: {
                $0.characterIDs.contains(character.id) && replyingIDs.contains($0.id)
            }) else { continue }
            for chat in conversations where (conversationID == nil || chat.id == conversationID) && chat.characterIDs.contains(character.id) {
                let eligible = memorySources(in: chat.id, role: character.id)
                let checkpoint = memoryAutomation(for: character.id).processedThrough[chat.id.uuidString]
                let new: [ChatMessage]
                if let checkpoint { new = eligible.firstIndex(where: { $0.id == checkpoint }).map { Array(eligible.dropFirst($0 + 1)) } ?? [] }
                else { new = eligible }
                if new.count >= 5 {
                    do { try await prepareMemory(role: character.id, conversationID: chat.id, sourceIDs: new.map(\.id)) } catch { }
                    break
                }
            }
        }
    }
    private func memorySources(in id: UUID, role: String) -> [ChatMessage] {
        (conversation(id)?.messages ?? []).filter { $0.isUser && $0.delivery == .sent && $0.replyCharacterIDs.contains(role) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    func prepareMemory(role: String, conversationID: UUID, sourceIDs: [UUID]? = nil) async throws {
        guard ready, let character = character(role), conversation(conversationID)?.characterIDs.contains(role) == true,
              !preparingMemoryRoles.contains(role), !replyingIDs.contains(conversationID) else { throw AIChatError.busy }
        guard memoryAutomation(for: role).suggestions.count <= 15 else { throw CharacterMemoryError.tooLarge }
        let eligible = memorySources(in: conversationID, role: role)
        let selected = sourceIDs.map { Set($0) }
        var sources = Array(eligible.filter { selected?.contains($0.id) ?? true }.suffix(12))
        while sources.reduce(0, { $0 + $1.text.count }) > 24000 { sources.removeFirst() }
        guard let last = sources.last else { throw CharacterMemoryError.noSources }
        let input = MemoryExtractionInput(conversationID: conversationID, sources: sources, existing: try memoryFiles.documents(for: role))
        let attempt = MemoryExtractionAttempt(id: UUID(), conversationID: conversationID, messageIDs: sources.map(\.id))
        guard change({ value in
            var automation = value.memoryAutomation ?? MemoryAutomation(); var settings = automation.roles[role] ?? .init()
            settings.processedThrough[conversationID.uuidString] = last.id; settings.attempt = attempt
            automation.roles[role] = settings; value.memoryAutomation = automation
        }) else { throw ChatError.invalidHistory }
        preparingMemoryRoles.insert(role); defer { preparingMemoryRoles.remove(role) }
        do {
            var profile = configuration.profile(for: character); profile.appControl = false; profile.automaticStickers = false
            profile.maxOutputTokens = 2048
            var request = ChatReplyRequest(conversationID: conversationID, kind: .direct, groupName: "", members: [character], character: character,
                userMessage: .user("整理记忆候选", recipients: [role]), history: [], profile: profile)
            request.memoryExtraction = input
            let answer = try await provider.reply(to: request); try Task.checkCancellation()
            let suggestions = try input.suggestions(from: answer, characterID: role)
            let existingNow = try memoryFiles.documents(for: role)
            guard change({ value in
                guard var settings = value.memoryAutomation?.roles[role], settings.attempt?.id == attempt.id else { throw CharacterMemoryError.invalid }
                let additions = suggestions.filter { candidate in
                    !existingNow.contains(where: { $0.text == candidate.text }) && !settings.suggestions.contains(where: { $0.text == candidate.text }) && value.conversations.contains(where: {
                        $0.id == candidate.conversationID && $0.messages.contains(where: { $0.isUser && $0.id == candidate.sourceMessageID && $0.text.contains(candidate.sourceQuote) })
                    })
                }
                settings.suggestions.append(contentsOf: additions)
                settings.attempt?.status = .completed; settings.attempt?.generatedCount = additions.count
                value.memoryAutomation?.roles[role] = settings
            }) else { throw ChatError.invalidHistory }
        } catch {
            let saved = change { value in
                guard value.memoryAutomation?.roles[role]?.attempt?.id == attempt.id else { return }
                value.memoryAutomation?.roles[role]?.attempt?.status = .failed
                value.memoryAutomation?.roles[role]?.attempt?.failure = String(error.localizedDescription.prefix(300))
            }
            if !saved, history.memoryAutomation?.roles[role]?.attempt?.id == attempt.id {
                history.memoryAutomation?.roles[role]?.attempt?.status = .failed
                history.memoryAutomation?.roles[role]?.attempt?.failure = "保存失败，已停止自动重试。"
            }
            throw error
        }
    }
    @discardableResult
    func confirmMemorySuggestion(_ suggestion: MemorySuggestion, title: String, text: String) -> Bool {
        guard memoryAutomation(for: suggestion.characterID).suggestions.contains(where: { $0.id == suggestion.id }),
              conversation(suggestion.conversationID)?.messages.contains(where: {
                  $0.isUser && $0.delivery == .sent && $0.id == suggestion.sourceMessageID
                      && $0.replyCharacterIDs.contains(suggestion.characterID) && $0.text.contains(suggestion.sourceQuote)
              }) == true else { error = "来源消息已更改或删除，这条候选不再有效。"; return false }
        let note = CharacterMemoryDocument(id: suggestion.id, characterID: suggestion.characterID, title: title, text: text, modifiedAt: .now)
        guard saveMemory(note) else { return false }
        if discardMemorySuggestion(suggestion) { return true }
        error = "记忆文件已保存，待确认列表更新失败，请稍后重试。"; return false
    }
    @discardableResult
    func discardMemorySuggestion(_ suggestion: MemorySuggestion) -> Bool {
        change { value in value.memoryAutomation?.roles[suggestion.characterID]?.suggestions.removeAll { $0.id == suggestion.id } }
    }

    private func canChangeMemory(for role: String) -> Bool {
        guard ready, availableIDs.contains(role) else { error = CharacterMemoryError.invalid.localizedDescription; return false }
        guard !conversations.contains(where: { $0.characterIDs.contains(role) && replyingIDs.contains($0.id) }),
              !proactiveState.slots.contains(where: { $0.characterID == role && preparingProactiveIDs.contains($0.id) }) else {
            error = "请等这位角色当前的回复或消息准备结束，再编辑记忆。"; return false
        }
        return true
    }
    private func invalidateMemoryQueue(for role: String) -> Bool {
        change { value in
            guard var state = value.proactive else { return }
            for index in state.slots.indices where state.slots[index].characterID == role && [.planned, .ready].contains(state.slots[index].status) {
                state.slots[index].status = .cancelled
            }
            var policies = state.characterPolicies ?? [:]; policies[role] = UUID()
            state.characterPolicies = policies; state.completedWindows?.removeValue(forKey: role)
            value.proactive = state
        }
    }
    @discardableResult
    func saveMemory(_ document: CharacterMemoryDocument) -> Bool {
        guard canChangeMemory(for: document.characterID) else { return false }
        do {
            try document.validate()
            let current = try memoryFiles.documents(for: document.characterID)
            if current.contains(where: { $0.id == document.id && $0.data == document.data }) { error = nil; return true }
            var next = current.filter { $0.id != document.id }
            next.append(document); try CharacterMemoryDocument.validate(next)
            guard invalidateMemoryQueue(for: document.characterID) else { return false }
            try memoryFiles.save(document); memoryRevision += 1; error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult
    func deleteMemory(_ document: CharacterMemoryDocument) -> Bool {
        guard canChangeMemory(for: document.characterID), invalidateMemoryQueue(for: document.characterID) else { return false }
        do { try memoryFiles.delete(document); memoryRevision += 1; error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult
    func clearMemories(for role: String) -> Bool {
        guard canChangeMemory(for: role) else { return false }
        do {
            let folder = try memoryFiles.folder(role)
            if FileManager.default.fileExists(atPath: folder.path) {
                let containsFiles = !(try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty
                if containsFiles { guard invalidateMemoryQueue(for: role) else { return false } }
                try FileManager.default.removeItem(at: folder)
            }
            memoryRevision += 1; error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult
    func editStoredMessage(_ messageID: UUID, in conversationID: UUID, text: String) -> Bool {
        guard replyingIDs.isEmpty, preparingProactiveIDs.isEmpty else { error = AIChatError.busy.localizedDescription; return false }
        return change { value in
            guard let c = value.conversations.firstIndex(where: { $0.id == conversationID }),
                  let m = value.conversations[c].messages.firstIndex(where: { $0.id == messageID }) else { throw ChatError.missingConversation }
            value.conversations[c].messages[m].text = text
            value.cancelProactiveChats(in: conversationID)
        }
    }
    @discardableResult
    func deleteStoredMessage(_ messageID: UUID, in conversationID: UUID) -> Bool {
        guard replyingIDs.isEmpty, preparingProactiveIDs.isEmpty else { error = AIChatError.busy.localizedDescription; return false }
        return change { value in
            guard let c = value.conversations.firstIndex(where: { $0.id == conversationID }) else { throw ChatError.missingConversation }
            value.conversations[c].messages.removeAll { $0.id == messageID || $0.replyToID == messageID }
            value.cancelProactiveChats(in: conversationID)
            if let indices = value.proactive?.slots.indices {
                for i in indices where value.proactive?.slots[i].id == messageID { value.proactive?.slots[i].status = .cancelled }
            }
        }
    }

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
        guard replyingIDs.isEmpty, preparingProactiveIDs.isEmpty, preparingMemoryRoles.isEmpty else { throw AIChatError.busy }
        var files: [String: Data] = [:]
        var total = 0
        for asset in history.mediaAssets {
            let bytes = try media.data(for: asset); total += bytes.count
            guard total <= ChatBackup.maximumSize * 3 / 4 else { throw AIChatError.backupTooLarge }
            files[asset.filename] = bytes
        }
        let data = try JSONEncoder().encode(ChatBackup(history: history, media: files, memories: memoryFiles.snapshot()))
        guard data.count <= ChatBackup.maximumSize else { throw AIChatError.backupTooLarge }
        return data
    }

    @discardableResult
    func importBackup(_ data: Data) -> Bool {
        guard replyingIDs.isEmpty, preparingProactiveIDs.isEmpty, preparingMemoryRoles.isEmpty else { error = AIChatError.busy.localizedDescription; return false }
        do {
            let backup = try ChatBackup.decode(data)
            for bytes in backup.media?.values ?? Dictionary<String, Data>().values { try media.store(bytes) }
            var restored = backup.history
            restored.recoverInterruptedReplies()
            restored.recoverInterruptedProactivePlans()
            restored.recoverInterruptedMemoryPreparations()
            restored.pruneMemorySuggestions()
            if let memories = backup.memories {
                let staging = try memoryFiles.stage(memories)
                var previous: URL?
                do { previous = try memoryFiles.install(staging: staging) }
                catch { try? FileManager.default.removeItem(at: staging); throw error }
                do { try file.save(restored) }
                catch {
                    do { try memoryFiles.rollback(previous: previous) }
                    catch { ready = false; throw CharacterMemoryError.unreadable }
                    throw error
                }
                if let previous { try? FileManager.default.removeItem(at: previous) }
            } else { try file.save(restored) }
            history = restored; ready = true; error = nil
            memoryRevision += 1
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func stop(_ id: UUID) { tasks[id]?.cancel() }

    func reload() {
        guard tasks.isEmpty, preparingProactiveIDs.isEmpty, preparingMemoryRoles.isEmpty else { return }
        do {
            var loaded = try file.load()
            loaded.recoverInterruptedReplies()
            loaded.recoverInterruptedProactivePlans()
            loaded.recoverInterruptedMemoryPreparations()
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
            next.pruneMemorySuggestions()
            if next == history { return true }
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
        return change { value in
            let previous = value.conversations.first { $0.id == id }?.characterIDs
            try value.editGroup(id, name: name, characterIDs: characterIDs, availableIDs: availableIDs)
            if previous != value.conversations.first(where: { $0.id == id })?.characterIDs { value.cancelProactiveChats(in: id) }
        }
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
        if change({ value in
            value.cancelProactiveChats(in: id)
            value.conversations.removeAll { $0.id == id }
        }) {
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
            value.cancelProactiveChats(in: id)
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
                    if !Task.isCancelled {
                        Task { [weak self] in await self?.prepareAutomaticMemories(in: id) }
                    }
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
                        $0.isUser ? allowedTurns.contains($0.id) : ($0.isProactive == true && $0.createdAt <= message.createdAt) || $0.replyToID.map(allowedTurns.contains) == true
                    }
                    var request = ChatReplyRequest(conversationID: id, kind: chat.kind, groupName: chat.name,
                        members: members, character: character, userMessage: message, history: turnHistory,
                        profile: preferences.profile(for: character), userProfile: preferences.user)
                    request.stickers = stickers(for: recipient)
                    request.memories = try memoryFiles.documents(for: recipient)
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

    func stickers(for characterID: String) -> [CharacterSticker] {
        let custom = (history.stickers ?? []).filter { $0.characterID == characterID }
        let ids = Set(custom.map(\.id))
        return custom + builtinStickers.filter { $0.characterID == characterID && !ids.contains($0.id) }
    }
    func isBuiltinSticker(_ id: UUID) -> Bool { builtinStickers.contains { $0.id == id } }

    @discardableResult
    func addSticker(data: Data, characterID: String, name: String, meaning: String) -> Bool {
        do {
            guard availableIDs.contains(characterID), (history.stickers ?? []).filter({ $0.characterID == characterID }).count < 100 else { throw ChatMediaError.limit }
            let asset = try media.store(data)
            let sticker = CharacterSticker(id: UUID(), characterID: characterID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), meaning: meaning, asset: asset)
            try sticker.validate()
            return change { $0.stickers = ($0.stickers ?? []) + [sticker] }
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeSticker(_ id: UUID) { guard !isBuiltinSticker(id) else { return }; change { $0.stickers?.removeAll { $0.id == id } } }
    func editSticker(_ id: UUID, name: String, meaning: String, data: Data? = nil) -> Bool {
        guard !isBuiltinSticker(id) else { return false }
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
        do {
            try item.validate()
            // Cache only a used built-in. Existing message snapshots must remain
            // readable if a later App version changes the bundled display copy.
            if item.kind == .sticker { _ = try media.store(try media.data(for: item.asset)) }
        } catch { self.error = error.localizedDescription; return false }
        return change { value in
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

    var proactiveState: ProactiveChatState { history.proactive ?? ProactiveChatState() }

    @discardableResult
    func saveProactiveSettings(_ settings: ProactiveChatSettings) -> Bool {
        change { value in
            try settings.validate()
            for (characterID, preference) in settings.characters where settings.enabled && preference.enabled {
                guard self.availableIDs.contains(characterID) else { throw ProactiveChatError.invalidSettings }
                if preference.destination == .group {
                    guard value.conversations.contains(where: { $0.id == preference.groupID && $0.kind == .group && $0.characterIDs.contains(characterID) }) else {
                        throw ProactiveChatError.invalidGroup(self.character(characterID)?.name ?? characterID)
                    }
                }
            }
            var state = value.proactive ?? ProactiveChatState()
            let ids = Set(state.settings.characters.keys).union(settings.characters.keys)
            for id in ids where !state.settings.preference(for: id).hasSameSchedule(as: settings.preference(for: id))
                || (state.settings.dailyCount != settings.dailyCount && settings.preference(for: id).intervalMinutes == nil) {
                for index in state.slots.indices where state.slots[index].characterID == id && [.planned, .ready].contains(state.slots[index].status) {
                    state.slots[index].status = .cancelled
                }
                var policies = state.characterPolicies ?? [:]
                policies[id] = UUID()
                state.characterPolicies = policies
                state.completedWindows?.removeValue(forKey: id)
            }
            state.settings = settings
            value.proactive = state
        }
    }

    @discardableResult
    func saveProactivePreference(_ preference: ProactiveCharacterSettings, for characterID: String) -> Bool {
        guard availableIDs.contains(characterID) else { error = ProactiveChatError.invalidSettings.localizedDescription; return false }
        var settings = proactiveState.settings
        // The former master switch may be off with role switches still on.
        // Enabling one role must not accidentally enable the others.
        if !settings.enabled {
            for id in Array(settings.characters.keys) { settings.characters[id]?.enabled = false }
        }
        settings.characters[characterID] = preference
        settings.enabled = settings.characters.values.contains { $0.enabled }
        return saveProactiveSettings(settings)
    }

    func planProactiveChats(now: Date = .now) -> [UUID] {
        var ids: [UUID] = []
        return change { ids = try $0.planProactiveChats(characters: characters, now: now) } ? ids : []
    }

    func prepareProactiveChat(_ slotID: UUID) async throws {
        guard !preparingProactiveIDs.contains(slotID),
              let slot = history.proactive?.slots.first(where: { $0.id == slotID }), slot.status == .planned else { return }
        preparingProactiveIDs.insert(slotID)
        defer { preparingProactiveIDs.remove(slotID) }
        do {
            guard proactiveState.settings.enabled, slot.policyID == proactiveState.policy(for: slot.characterID),
                  proactiveState.settings.characters[slot.characterID]?.enabled == true,
                  let chat = conversation(slot.conversationID), chat.characterIDs.contains(slot.characterID),
                  let character = character(slot.characterID) else { throw ProactiveChatError.unavailable }
            guard slot.scheduledAt > .now else { throw ProactiveChatError.expired }
            var profile = configuration.profile(for: character)
            // Preparing a future greeting must never execute App writes or sticker tools.
            profile.appControl = false; profile.automaticStickers = false
            profile.maxOutputTokens = min(profile.maxOutputTokens, 4096)
            let instruction = ChatMessage.user("请准备一句自然的主动聊天开场，不超过 120 字；不要声称用户刚说了什么。", recipients: [character.id])
            var request = ChatReplyRequest(conversationID: chat.id, kind: chat.kind, groupName: chat.name,
                members: chat.characterIDs.compactMap { self.character($0) }, character: character,
                userMessage: instruction, history: chat.messages, profile: profile, userProfile: configuration.user)
            request.proactiveDeliveryDate = slot.scheduledAt
            request.memories = try memoryFiles.documents(for: character.id)
            let answer = try await provider.reply(to: request).trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !answer.isEmpty, answer.count <= 1800 else { throw ChatError.emptyReply }
            guard slot.scheduledAt > .now else { throw ProactiveChatError.expired }
            guard change({ value in
                guard var state = value.proactive, state.settings.enabled, state.policy(for: slot.characterID) == slot.policyID,
                      state.settings.characters[slot.characterID]?.enabled == true,
                      let index = state.slots.firstIndex(where: { $0.id == slotID && $0.status == .planned }),
                      value.conversations.contains(where: { $0.id == chat.id && $0.characterIDs.contains(character.id) }) else { throw ProactiveChatError.unavailable }
                let nickname = value.configuration?.user.nickname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                state.slots[index].text = (chat.kind == .group ? "@\(nickname.isEmpty ? "我" : nickname) " : "") + answer
                state.slots[index].status = .ready
                value.proactive = state
            }) else { throw ProactiveChatError.unavailable }
        } catch {
            let saved = change { value in
                guard let index = value.proactive?.slots.firstIndex(where: { $0.id == slotID && $0.status == .planned }) else { return }
                value.proactive?.slots[index].status = .failed
                value.proactive?.slots[index].failure = String(error.localizedDescription.prefix(300))
            }
            // A failed disk write must not leave an in-memory planned slot that
            // the foreground scheduler will repeatedly send to the paid API.
            if !saved, let index = history.proactive?.slots.firstIndex(where: { $0.id == slotID && $0.status == .planned }) {
                history.proactive?.slots[index].status = .failed
                history.proactive?.slots[index].failure = "消息保存失败，已停止自动准备；请检查存储后手动重试。"
            }
            throw error
        }
    }

    func deliverProactiveChats(now: Date = .now) -> [UUID] {
        guard history.proactive?.slots.contains(where: { $0.status == .ready && $0.scheduledAt <= now }) == true else { return [] }
        var ids: [UUID] = []
        return change { ids = try $0.deliverProactiveChats(now: now) } ? ids : []
    }

    func setProactiveNotificationScheduled(_ id: UUID, scheduled: Bool) {
        _ = change { value in
            guard let index = value.proactive?.slots.firstIndex(where: { $0.id == id }) else { return }
            value.proactive?.slots[index].notificationScheduled = scheduled
        }
    }

    func retryProactivePreparations(now: Date = .now, characterID: String? = nil) {
        _ = change { value in
            guard let state = value.proactive, state.settings.enabled else { return }
            for index in state.slots.indices where state.slots[index].status == .failed
                && (characterID == nil || state.slots[index].characterID == characterID)
                && state.slots[index].policyID == state.policy(for: state.slots[index].characterID) && state.slots[index].scheduledAt > now.addingTimeInterval(60) {
                value.proactive?.slots[index].status = .planned
                value.proactive?.slots[index].failure = nil
            }
        }
    }

    func markRead(_ id: UUID, now: Date = .now) {
        guard (conversation(id)?.unreadProactiveCount ?? 0) > 0 else { return }
        _ = change { value in
            guard let index = value.conversations.firstIndex(where: { $0.id == id }) else { return }
            value.conversations[index].lastReadAt = now
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
            _ = try media.store(try media.data(for: sticker.asset))
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
