import Foundation
import XCTest
@testable import DragonDomain

final class ChatTests: XCTestCase {
    private let available: Set<String> = ["xiaobai", "future"]

    func testDirectConversationIsReusedAndDifferentCharactersStaySeparate() throws {
        var history = ChatHistory()
        let first = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: available)
        let same = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: available)
        let other = try history.create(kind: .direct, name: "", characterIDs: ["future"], availableIDs: available)
        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(history.conversations.count, 2)
    }

    func testGroupAllowsOneCharacterAndDeduplicatesMembers() throws {
        var history = ChatHistory()
        let id = try history.create(kind: .group, name: " 小白的家 ", characterIDs: ["xiaobai", "xiaobai"], availableIDs: available)
        XCTAssertEqual(history.conversations[0].name, "小白的家")
        XCTAssertEqual(history.conversations[0].characterIDs, ["xiaobai"])
        let direct = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: available)
        XCTAssertNotEqual(id, direct)
    }

    func testInvalidMembersNamesAndDirectGroupsAreRejected() {
        var history = ChatHistory()
        for members in [[], ["unknown"]] as [[String]] {
            XCTAssertThrowsError(try history.create(kind: .group, name: "群", characterIDs: members, availableIDs: available))
        }
        XCTAssertThrowsError(try history.create(kind: .direct, name: "", characterIDs: ["xiaobai", "future"], availableIDs: available))
        XCTAssertThrowsError(try history.create(kind: .group, name: " \n", characterIDs: ["xiaobai"], availableIDs: available))
        XCTAssertThrowsError(try history.create(kind: .group, name: String(repeating: "白", count: 31), characterIDs: ["xiaobai"], availableIDs: available))
        XCTAssertTrue(history.conversations.isEmpty)
    }

    func testSendingKeepsMultilineContentAndFreezesTurnRecipients() throws {
        var history = ChatHistory()
        let id = try history.create(kind: .group, name: "群", characterIDs: ["xiaobai", "future"], availableIDs: available)
        history.conversations[0].draft = "草稿"
        let message = try history.enqueue("  你好\n今天怎么样？  ", in: id, availableIDs: available)
        XCTAssertEqual(message.text, "你好\n今天怎么样？")
        XCTAssertEqual(message.replyCharacterIDs, ["xiaobai", "future"])
        XCTAssertEqual(message.delivery, .waiting)
        XCTAssertEqual(history.conversations[0].draft, "")
        XCTAssertThrowsError(try history.enqueue("第二条", in: id, availableIDs: available))
        XCTAssertThrowsError(try history.editGroup(id, name: "新群", characterIDs: ["future"], availableIDs: available))
    }

    func testEmptyOversizeAndUnavailableMessagesDoNotAppend() throws {
        var history = ChatHistory()
        let id = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: available)
        XCTAssertThrowsError(try history.enqueue("\n  ", in: id, availableIDs: available))
        XCTAssertThrowsError(try history.enqueue(String(repeating: "白", count: 4001), in: id, availableIDs: available))
        XCTAssertThrowsError(try history.enqueue("你好", in: id, availableIDs: []))
        XCTAssertTrue(history.conversations[0].messages.isEmpty)
        XCTAssertNoThrow(try history.enqueue(String(repeating: "白", count: 4000), in: id, availableIDs: available))
    }

    func testPartialGroupRepliesRecoverWithoutDuplicatingSuccessfulMember() throws {
        var history = ChatHistory()
        let id = try history.create(kind: .group, name: "群", characterIDs: ["xiaobai", "future"], availableIDs: available)
        let message = try history.enqueue("你好", in: id, availableIDs: available)
        history.conversations[0].messages.append(.reply("聊天功能测试中", character: .xiaobai, to: message.id))
        history.recoverInterruptedReplies()
        XCTAssertEqual(history.conversations[0].messages[0].delivery, .failed)
        XCTAssertEqual(history.conversations[0].missingReplies(to: message), ["future"])
        try history.editGroup(id, name: "新群", characterIDs: ["xiaobai"], availableIDs: available)
        XCTAssertEqual(history.conversations[0].messages[0].replyCharacterIDs, ["xiaobai", "future"])
        XCTAssertEqual(history.conversations[0].messages.count, 2)
    }

    func testCompletedTurnInterruptedBeforeStatusWriteRecoversAsSent() throws {
        var history = ChatHistory()
        let id = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: available)
        let message = try history.enqueue("你好", in: id, availableIDs: available)
        history.conversations[0].messages.append(.reply("聊天功能测试中", character: .xiaobai, to: message.id))
        history.recoverInterruptedReplies()
        XCTAssertEqual(history.conversations[0].messages[0].delivery, .sent)
    }

    func testHistoryAndDraftSurviveDiskRoundTripAndCorruptionIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ChatHistoryFile(url: directory.appendingPathComponent("Chat/history.json"))
        XCTAssertTrue(try file.load().conversations.isEmpty)
        var history = ChatHistory()
        let id = try history.create(kind: .group, name: "家", characterIDs: ["xiaobai", "future"], availableIDs: available)
        _ = try history.enqueue("你好", in: id, availableIDs: available)
        history.conversations[0].draft = "下次再说"
        try file.save(history)
        XCTAssertEqual(try file.load(), history)
        let corrupt = Data("broken history".utf8)
        try corrupt.write(to: file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf: file.url), corrupt)
    }

    func testUnsupportedHistoryAndDuplicateConversationsAreRejected() throws {
        var history = ChatHistory()
        history.version = 2
        XCTAssertThrowsError(try history.validate())
        history.version = 1
        _ = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: available)
        history.conversations.append(history.conversations[0])
        XCTAssertThrowsError(try history.validate())
    }

    func testMockProviderReturnsExactTextAndHonorsCancellation() async throws {
        let message = ChatMessage.user("你好", recipients: ["xiaobai"])
        let request = ChatReplyRequest(conversationID: UUID(), kind: .direct, groupName: "", members: [.xiaobai],
                                       character: .xiaobai, userMessage: message, history: [message])
        let text = try await TestChatReplyProvider().reply(to: request)
        XCTAssertEqual(text, "聊天功能测试中")
        let task = Task { try await TestChatReplyProvider().reply(to: request) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled requests must not produce replies") }
        catch is CancellationError { }
    }
}
