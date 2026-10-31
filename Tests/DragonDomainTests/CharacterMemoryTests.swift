import Foundation
import XCTest
@testable import DragonDomain

final class CharacterMemoryFileTests: XCTestCase {
    private func note(_ role: String = "xiaobai", text: String = "喜欢喝茶，也喜欢海边。") -> CharacterMemoryDocument {
        .init(id: UUID(), characterID: role, title: "偏好", text: text, modifiedAt: .now)
    }
    func testIndependentRoleFilesUseActualUTF8BytesAndCanBeEditedAndDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = CharacterMemoryFiles(historyURL: root.appendingPathComponent("history.json"))
        var xiao = note(); let fish = note("dafeiyu", text: "喜欢甜点。")
        try files.save(xiao); try files.save(fish)
        XCTAssertEqual(try files.actualByteCount(of: xiao), xiao.data.count)
        XCTAssertGreaterThan(xiao.byteCount, xiao.text.count)
        XCTAssertNotEqual(try files.url(for: xiao).deletingLastPathComponent(), try files.url(for: fish).deletingLastPathComponent())
        xiao.text = "现在喜欢清茶。"; try files.save(xiao)
        XCTAssertEqual(try files.documents(for: "xiaobai").count, 1)
        XCTAssertEqual(try files.documents(for: "xiaobai").first?.text, xiao.text)
        try files.delete(xiao)
        XCTAssertTrue(try files.documents(for: "xiaobai").isEmpty)
        XCTAssertEqual(try files.documents(for: "dafeiyu").first?.text, fish.text)
    }
    func testInvalidPathsSymlinksAndOversizedNotesNeverOverwriteOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = CharacterMemoryFiles(historyURL: root.appendingPathComponent("history.json"))
        XCTAssertThrowsError(try files.save(note("../dafeiyu")))
        XCTAssertThrowsError(try files.save(note(text: String(repeating: "a", count: 6001))))
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: files.directory.appendingPathComponent("xiaobai"), withDestinationURL: outside)
        XCTAssertThrowsError(try files.save(note()))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
    func testRoleBudgetRejectsExtraNoteWithoutDamagingExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = CharacterMemoryFiles(historyURL: root.appendingPathComponent("history.json"))
        try files.save(note(text: String(repeating: "a", count: 6000)))
        try files.save(note(text: String(repeating: "b", count: 6000)))
        XCTAssertThrowsError(try files.save(note(text: "再加一个字")))
        XCTAssertEqual(try files.snapshot().count, 2)
    }
    func testMemoryContextIsRoleScopedEvenWithZeroHistoryAndForgedCrossRoleInput() throws {
        var profile = AICharacterProfile(); profile.contextRounds = 0
        var request = ChatReplyRequest(conversationID: UUID(), kind: .direct, groupName: "", members: [.xiaobai],
            character: .xiaobai, userMessage: .user("你好", recipients: ["xiaobai"]), history: [], profile: profile)
        request.memories = [note(text: "小白专属记忆"), note("dafeiyu", text: "大肥鱼私密记忆")]
        let messages = try AIChatContext.messages(for: request)
        XCTAssertTrue(messages[0].content.contains("小白专属记忆"))
        XCTAssertFalse(messages[0].content.contains("大肥鱼私密记忆"))
        XCTAssertEqual(messages.count, 2)
    }
    func testExtractionRejectsInventedEvidenceAIStatementsAndCredentialMemories() throws {
        var user = ChatMessage.user("我喜欢喝无糖绿茶。", recipients: ["xiaobai"]); user.delivery = .sent
        let input = MemoryExtractionInput(conversationID: UUID(), sources: [user], existing: [])
        func answer(_ quote: String, text: String = "喜欢无糖绿茶", id: UUID? = nil) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["items":[["title":"饮品","text":text,"sourceMessageID":(id ?? user.id).uuidString,"sourceQuote":quote]]])
            return String(decoding: data, as: UTF8.self)
        }
        XCTAssertEqual(try input.suggestions(from: answer(user.text), characterID: "xiaobai").count, 1)
        XCTAssertThrowsError(try input.suggestions(from: answer("我喜欢喝咖啡。"), characterID: "xiaobai"))
        XCTAssertThrowsError(try input.suggestions(from: answer(user.text, id: UUID()), characterID: "xiaobai"))
        XCTAssertThrowsError(try input.suggestions(from: answer(user.text, text: "sk-" + String(repeating: "x", count: 32)), characterID: "xiaobai"))
        XCTAssertThrowsError(try input.messages(characterID: "dafeiyu"))
    }
}

private actor MemoryTestProvider: ChatReplyProvider {
    private(set) var requests: [ChatReplyRequest] = []
    private(set) var extractionCount = 0
    let failFirstExtraction: Bool
    init(failFirstExtraction: Bool = false) { self.failFirstExtraction = failFirstExtraction }
    func reply(to request: ChatReplyRequest) async throws -> String {
        requests.append(request)
        guard let input = request.memoryExtraction else { return "收到你的消息。" }
        extractionCount += 1
        if failFirstExtraction && extractionCount == 1 { throw AIChatError.network }
        let source = input.sources.last!
        let data = try JSONSerialization.data(withJSONObject: ["items":[["title":"饮品偏好","text":"喜欢无糖绿茶",
            "sourceMessageID":source.id.uuidString,"sourceQuote":source.text]]])
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
final class CharacterMemoryStoreTests: XCTestCase {
    private func make(provider: any ChatReplyProvider = MemoryTestProvider()) -> (ChatStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")), provider: provider), root)
    }
    private func settle(_ store: ChatStore) async throws {
        for _ in 0..<400 {
            try await Task.sleep(nanoseconds: 10_000_000)
            if store.replyingIDs.isEmpty && store.preparingMemoryRoles.isEmpty {
                try await Task.sleep(nanoseconds: 20_000_000)
                if store.replyingIDs.isEmpty && store.preparingMemoryRoles.isEmpty { return }
            }
        }
        XCTFail("Requests did not settle")
    }
    private func send(_ store: ChatStore, _ id: UUID) async throws {
        XCTAssertTrue(store.send("我喜欢喝无糖绿茶。", in: id)); try await settle(store)
    }
    func testAutomaticMemoryReservesPaidBatchAndRequiresConfirmationBeforeAnyFileOrPromptUse() async throws {
        let provider = MemoryTestProvider(); let (store, root) = make(provider: provider)
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        try await send(store, chat)
        XCTAssertTrue(store.setAutomaticMemory(true, for: "xiaobai"))
        for _ in 0..<4 { try await send(store, chat) }
        var count = await provider.extractionCount; XCTAssertEqual(count, 0, "Enabling must not process the whole old archive")
        try await send(store, chat)
        count = await provider.extractionCount; XCTAssertEqual(count, 1)
        XCTAssertTrue(try store.memoryFiles.snapshot().isEmpty)
        let suggestion = try XCTUnwrap(store.memoryAutomation(for: "xiaobai").suggestions.first)
        let requests = await provider.requests
        XCTAssertTrue(requests.filter { $0.memoryExtraction == nil }.allSatisfy { $0.memories.isEmpty })
        let extraction = try XCTUnwrap(requests.first(where: { $0.memoryExtraction != nil }))
        XCTAssertTrue(ChatTools.allowed(for: extraction).isEmpty)
        XCTAssertTrue(extraction.history.isEmpty)
        XCTAssertTrue(extraction.memoryExtraction!.sources.allSatisfy(\.isUser))
        XCTAssertTrue(store.confirmMemorySuggestion(suggestion, title: suggestion.title, text: suggestion.text))
        XCTAssertEqual(try store.memoryFiles.snapshot().count, 1)
        XCTAssertTrue(store.memoryAutomation(for: "xiaobai").suggestions.isEmpty)
        try await send(store, chat)
        let latest = await provider.requests.last!
        XCTAssertEqual(latest.memories.first?.text, "喜欢无糖绿茶")
        for _ in 0..<3 { await store.prepareAutomaticMemories() }
        count = await provider.extractionCount; XCTAssertEqual(count, 1)
    }
    func testFailedExtractionIsNotAutomaticallyChargedAgainAfterReopenAndExplicitRetryCanRecover() async throws {
        let provider = MemoryTestProvider(failFirstExtraction: true); let (store, root) = make(provider: provider)
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.setAutomaticMemory(true, for: "xiaobai"))
        for _ in 0..<5 { try await send(store, chat) }
        let attempt = try XCTUnwrap(store.memoryAutomation(for: "xiaobai").attempt)
        XCTAssertEqual(attempt.status, .failed)
        let restored = ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")), provider: provider)
        for _ in 0..<3 { await restored.prepareAutomaticMemories() }
        var count = await provider.extractionCount; XCTAssertEqual(count, 1)
        try await restored.prepareMemory(role: "xiaobai", conversationID: chat, sourceIDs: attempt.messageIDs)
        count = await provider.extractionCount; XCTAssertEqual(count, 2)
        XCTAssertEqual(restored.memoryAutomation(for: "xiaobai").suggestions.count, 1)
        XCTAssertTrue(try restored.memoryFiles.snapshot().isEmpty)
    }
    func testSourceDeletionRemovesPendingSuggestionAndEditingStoredContextDoesNotSendAgain() async throws {
        let provider = MemoryTestProvider(); let (store, root) = make(provider: provider)
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        try await send(store, chat)
        try await store.prepareMemory(role: "xiaobai", conversationID: chat)
        XCTAssertEqual(store.memoryAutomation(for: "xiaobai").suggestions.count, 1)
        let parent = try XCTUnwrap(store.conversation(chat)?.messages.first)
        let count = await provider.requests.count
        XCTAssertTrue(store.editStoredMessage(parent.id, in: chat, text: "我喜欢喝乌龙茶。"))
        XCTAssertTrue(store.memoryAutomation(for: "xiaobai").suggestions.isEmpty)
        XCTAssertEqual(store.conversation(chat)?.messages.count, 2)
        XCTAssertTrue(store.deleteStoredMessage(parent.id, in: chat))
        XCTAssertTrue(store.conversation(chat)!.messages.isEmpty)
        let after = await provider.requests.count; XCTAssertEqual(after, count)
        XCTAssertNoThrow(try store.history.validate())
    }
    func testBackupV3RestoresActualFilesAndLegacyBackupDoesNotSilentlyEraseNewMemory() throws {
        let (store, root) = make(); let (restored, other) = make()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
        let note = CharacterMemoryDocument(id: UUID(), characterID: "xiaobai", title: "约定", text: "喜欢安静的清晨。", modifiedAt: .now)
        XCTAssertTrue(store.saveMemory(note))
        let data = try store.exportBackup()
        XCTAssertEqual(try ChatBackup.decode(data).version, 3)
        XCTAssertTrue(restored.importBackup(data))
        let loaded = try XCTUnwrap(restored.memoryFiles.documents(for: "xiaobai").first)
        XCTAssertEqual(loaded.id, note.id); XCTAssertEqual(loaded.text, note.text)
        XCTAssertEqual(try Data(contentsOf: restored.memoryFiles.url(for: loaded)), note.data)
        let legacy = try JSONEncoder().encode(ChatBackup(history: ChatHistory()))
        XCTAssertTrue(restored.importBackup(legacy))
        XCTAssertEqual(try restored.memoryFiles.snapshot().first?.text, note.text)
    }
    func testHistorySaveFailureDuringRestoreRollsBackMemoryDirectory() throws {
        let (store, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = CharacterMemoryDocument(id: UUID(), characterID: "xiaobai", title: "原记忆", text: "原内容仍需保留。", modifiedAt: .now)
        XCTAssertTrue(store.saveMemory(original))
        let replacement = CharacterMemoryDocument(id: UUID(), characterID: "xiaobai", title: "新记忆", text: "不应覆盖原文件。", modifiedAt: .now)
        let backup = try JSONEncoder().encode(ChatBackup(history: ChatHistory(), media: [:], memories: [replacement]))
        try FileManager.default.createDirectory(at: store.historyFileURL, withIntermediateDirectories: true)
        XCTAssertFalse(store.importBackup(backup))
        XCTAssertEqual(try store.memoryFiles.snapshot().map(\.text), [original.text])
    }
    func testDeletingMemoryRemovesItFromSubsequentRequestsWithoutErasingChatHistory() async throws {
        let provider = MemoryTestProvider(); let (store, root) = make(provider: provider)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = CharacterMemoryDocument(id: UUID(), characterID: "xiaobai", title: "偏好", text: "喜欢清茶。", modifiedAt: .now)
        XCTAssertTrue(store.saveMemory(note))
        let chat = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        try await send(store, chat)
        XCTAssertTrue(store.deleteMemory(note))
        try await send(store, chat)
        let requests = await provider.requests
        XCTAssertEqual(requests[0].memories.count, 1)
        XCTAssertTrue(requests.last!.memories.isEmpty)
        XCTAssertEqual(store.conversation(chat)?.messages.count, 4)
    }
    func testUnchangedSaveKeepsPreparedQueueAndDeletionCancelsStaleMemoryGreetings() throws {
        let (store, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        var note = CharacterMemoryDocument(id: UUID(), characterID: "xiaobai", title: "偏好", text: "喜欢清茶。", modifiedAt: .now)
        XCTAssertTrue(store.saveMemory(note))
        XCTAssertTrue(store.saveProactivePreference(.init(enabled: true), for: "xiaobai"))
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        XCTAssertFalse(store.planProactiveChats(now: morning).isEmpty)
        let slots = store.proactiveState.slots
        note.modifiedAt = .now
        XCTAssertTrue(store.saveMemory(note))
        XCTAssertEqual(store.proactiveState.slots, slots)
        XCTAssertTrue(store.deleteMemory(note))
        XCTAssertTrue(store.proactiveState.slots.allSatisfy { $0.status == .cancelled })
    }
}
