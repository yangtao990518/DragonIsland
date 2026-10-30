import XCTest
@testable import DragonDomain

private actor MediaToolProvider: ChatReplyProvider {
    let calls: [ChatToolCall]
    let failFirst: Bool
    private var attempts = 0
    init(calls: [ChatToolCall], failFirst: Bool = false) { self.calls = calls; self.failFirst = failFirst }
    func reply(to request: ChatReplyRequest) async throws -> String { "测试回复" }
    func reply(to request: ChatReplyRequest, onPartial: @escaping @Sendable (String) async -> Void, onTool: @escaping ChatToolHandler) async throws -> String {
        attempts += 1
        var results: [String] = []
        for call in calls { results.append(try await onTool(call)) }
        if failFirst && attempts == 1 { throw AIChatError.network }
        return results.joined(separator: "\n")
    }
}

@MainActor
final class ChatMediaStoreTests: XCTestCase {
    private func store(provider: any ChatReplyProvider = TestChatReplyProvider()) -> (ChatStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")), provider: provider), root)
    }
    private func finish(_ store: ChatStore) async throws {
        for _ in 0..<300 {
            if store.replyingIDs.isEmpty { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("reply did not finish")
    }
    func testMediaDraftSurvivesRestartAndBackupRestoreKeepsGIFBytes() async throws {
        let (store, root) = store()
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        let gif = try ChatMediaToolTests.image(gif: true)
        XCTAssertTrue(store.attach(data: gif, in: id))
        let restarted = ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")))
        XCTAssertEqual(restarted.conversation(id)?.draftAttachments?.count, 1)
        let restored = ChatStore(characters: [.xiaobai], file: .init(url: other.appendingPathComponent("history.json")))
        XCTAssertTrue(restored.importBackup(try restarted.exportBackup()))
        let item = try XCTUnwrap(restored.conversation(id)?.draftAttachments?.first)
        XCTAssertEqual(try restored.media.data(for: item.asset), gif)
        XCTAssertTrue(store.send("", in: id))
        try await finish(store)
        XCTAssertNil(store.conversation(id)?.draftAttachments)
        XCTAssertEqual(store.conversation(id)?.messages.first?.attachments?.first?.asset, item.asset)
    }
    func testWriteIsExecutedOnceAcrossRepeatedCallsAndFailedTurnRetry() async throws {
        let call = ChatToolCall(id: "call-1", function: .init(name: "create_alarm", arguments: #"{"date":"2026-12-01T12:00:00+08:00","title":"测试"}"#))
        let (store, root) = store(provider: MediaToolProvider(calls: [call, call], failFirst: true))
        defer { try? FileManager.default.removeItem(at: root) }
        var preferences = store.configuration; var profile = AICharacterProfile(); profile.appControl = true
        preferences.characters["xiaobai"] = profile; XCTAssertTrue(store.saveConfiguration(preferences))
        var executions = 0
        store.appToolHandler = { _, _, _ in executions += 1; return "created-test-id" }
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.send("请设置提醒", in: id)); try await finish(store)
        XCTAssertEqual(executions, 1)
        let user = try XCTUnwrap(store.conversation(id)?.messages.first)
        XCTAssertEqual(user.delivery, .failed)
        store.retry(in: id, messageID: user.id); try await finish(store)
        XCTAssertEqual(executions, 1)
        XCTAssertEqual(store.conversation(id)?.messages.first?.delivery, .sent)
        XCTAssertEqual(store.conversation(id)?.messages.last?.text, "created-test-id\ncreated-test-id")
    }
    func testRolePermissionOffPreventsExecutionEvenIfProviderAsks() async throws {
        let call = ChatToolCall(id: "read", function: .init(name: "app_state", arguments: "{}"))
        let (store, root) = store(provider: MediaToolProvider(calls: [call]))
        defer { try? FileManager.default.removeItem(at: root) }
        var executions = 0
        store.appToolHandler = { _, _, _ in executions += 1; return "state" }
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.send("查看状态", in: id)); try await finish(store)
        XCTAssertEqual(executions, 0)
        XCTAssertTrue(store.conversation(id)?.messages.last?.text.contains("权限已关闭") == true)
    }
    func testAIStickerUsesOwnedSnapshotAndLibraryRemovalDoesNotBreakMessages() async throws {
        let (seed, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(seed.addSticker(data: try ChatMediaToolTests.image(gif: true), characterID: "xiaobai", name: "挥手", meaning: "打招呼"))
        let sticker = try XCTUnwrap(seed.stickers(for: "xiaobai").first)
        var configuration = seed.configuration; var profile = AICharacterProfile(); profile.automaticStickers = true
        configuration.characters["xiaobai"] = profile; XCTAssertTrue(seed.saveConfiguration(configuration))
        let call = ChatToolCall(id: "sticker", function: .init(name: "send_sticker", arguments: "{\"sticker_id\":\"\(sticker.id.uuidString)\"}"))
        let store = ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")), provider: MediaToolProvider(calls: [call, call]))
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.send("你好", in: id)); try await finish(store)
        XCTAssertEqual(store.conversation(id)?.messages.last?.attachments?.count, 1)
        XCTAssertTrue(store.editSticker(sticker.id, name: "新挥手", meaning: "挥手", data: try ChatMediaToolTests.image()))
        XCTAssertEqual(store.stickers(for: "xiaobai").first?.id, sticker.id)
        XCTAssertEqual(store.stickers(for: "xiaobai").first?.asset.animated, false)
        XCTAssertEqual(store.conversation(id)?.messages.last?.attachments?.first?.asset, sticker.asset)
        store.removeSticker(sticker.id)
        XCTAssertTrue(store.stickers(for: "xiaobai").isEmpty)
        let backup = try ChatBackup.decode(store.exportBackup())
        XCTAssertEqual(backup.media?[sticker.asset.filename], try ChatMediaToolTests.image(gif: true))
    }
}

