#if canImport(Combine)
import Foundation
import XCTest
@testable import DragonDomain

private actor RecordingChatProvider: ChatReplyProvider {
    var requests: [ChatReplyRequest] = []
    var failNext = false
    var slow = false
    func setFailure() { failNext = true }
    func setSlow() { slow = true }
    func reply(to request: ChatReplyRequest) async throws -> String {
        requests.append(request)
        if slow { try await Task.sleep(nanoseconds: 150_000_000) }
        if failNext { failNext = false; throw ChatError.emptyReply }
        try Task.checkCancellation()
        return "聊天功能测试中"
    }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    private var directory: URL!
    private var file: ChatHistoryFile { ChatHistoryFile(url: directory.appendingPathComponent("history.json")) }
    private var future: CompanionCharacter {
        CompanionCharacter(id: "future", name: "新朋友", subtitle: "测试角色", introduction: "", origin: "测试",
                           chibiAsset: "XiaobaiChibi", portraitAsset: "XiaobaiStanding", heroAsset: "XiaobaiHero",
                           chibiSource: "", standingSource: "")
    }

    override func setUp() async throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    private func settled(_ store: ChatStore) async throws {
        for _ in 0..<100 {
            if store.replyingIDs.isEmpty { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Reply task failed to finish")
    }

    func testGroupRepliesOncePerMemberAndPersistsAfterRelaunch() async throws {
        let provider = RecordingChatProvider()
        let store = ChatStore(characters: [.xiaobai, future], file: file, provider: provider)
        let id = try XCTUnwrap(store.create(kind: .group, name: "大家", characterIDs: ["xiaobai", "future"]))
        XCTAssertTrue(store.send("你好", in: id))
        XCTAssertFalse(store.send("重复点击", in: id))
        try await settled(store)
        let messages = try XCTUnwrap(store.conversation(id)).messages
        XCTAssertEqual(messages.map(\.text), ["你好", "聊天功能测试中", "聊天功能测试中"])
        XCTAssertEqual(messages.compactMap(\.characterID), ["xiaobai", "future"])
        XCTAssertEqual(messages.first?.delivery, .sent)
        let requests = await provider.requests
        XCTAssertEqual(requests.map { $0.character.id }, ["xiaobai", "future"])
        XCTAssertEqual(requests[1].members.count, 2)
        XCTAssertEqual(requests[0].history.last?.text, "你好")
        let relaunched = ChatStore(characters: [.xiaobai, future], file: file)
        XCTAssertEqual(relaunched.history, store.history)
    }

    func testRetryUsesOriginalTurnAndDoesNotDuplicateCompletedReplies() async throws {
        var initial = ChatHistory()
        let id = try initial.create(kind: .group, name: "群", characterIDs: ["xiaobai", "future"], availableIDs: ["xiaobai", "future"])
        let first = try initial.enqueue("第一条", in: id, availableIDs: ["xiaobai", "future"])
        initial.conversations[0].messages.append(.reply("已收到", character: .xiaobai, to: first.id))
        initial.recoverInterruptedReplies()
        _ = try initial.enqueue("第二条", in: id, availableIDs: ["xiaobai", "future"])
        initial.recoverInterruptedReplies()
        try file.save(initial)
        let provider = RecordingChatProvider()
        let store = ChatStore(characters: [.xiaobai, future], file: file, provider: provider)
        store.retry(in: id, messageID: first.id)
        try await settled(store)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].character.id, "future")
        XCTAssertFalse(requests[0].history.contains { $0.text == "第二条" })
        XCTAssertEqual(store.conversation(id)?.messages.filter { $0.replyToID == first.id }.count, 2)
    }

    func testProviderFailureCanBeRetried() async throws {
        let provider = RecordingChatProvider()
        await provider.setFailure()
        let store = ChatStore(characters: [.xiaobai], file: file, provider: provider)
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.send("你好", in: id))
        try await settled(store)
        let message = try XCTUnwrap(store.conversation(id)?.messages.first)
        XCTAssertEqual(message.delivery, .failed)
        store.retry(in: id, messageID: message.id)
        try await settled(store)
        XCTAssertEqual(store.conversation(id)?.messages.count, 2)
        XCTAssertEqual(store.conversation(id)?.messages.first?.delivery, .sent)
    }

    func testDeletingDuringReplyDoesNotResurrectConversation() async throws {
        let provider = RecordingChatProvider()
        await provider.setSlow()
        let store = ChatStore(characters: [.xiaobai], file: file, provider: provider)
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.send("你好", in: id))
        try await Task.sleep(nanoseconds: 30_000_000)
        store.delete(id)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(store.conversation(id))
        XCTAssertTrue(try file.load().conversations.isEmpty)
    }

    func testDraftEditingAndClearArePersisted() throws {
        let store = ChatStore(characters: [.xiaobai, future], file: file)
        let id = try XCTUnwrap(store.create(kind: .group, name: "旧群", characterIDs: ["xiaobai"]))
        store.setDraft("稍后发送", in: id)
        XCTAssertTrue(store.editGroup(id, name: "新群", characterIDs: ["xiaobai", "future"]))
        XCTAssertEqual(try file.load().conversations.first?.draft, "稍后发送")
        XCTAssertEqual(store.conversation(id)?.characterIDs, ["xiaobai", "future"])
        XCTAssertTrue(store.clear(id))
        XCTAssertEqual(try file.load().conversations.first?.draft, "")
    }

    func testCorruptHistoryCannotBeOverwrittenByCreate() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("bad history".utf8)
        try corrupt.write(to: file.url)
        let store = ChatStore(characters: [.xiaobai], file: file)
        XCTAssertFalse(store.ready)
        XCTAssertNil(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertEqual(try Data(contentsOf: file.url), corrupt)
    }
}
#endif
