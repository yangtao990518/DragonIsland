import Foundation
import XCTest
@testable import DragonDomain

private final class ChatURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.respond!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class AIChatTests: XCTestCase {
    private func request(profile: AICharacterProfile = AICharacterProfile(), kind: ChatKind = .direct,
                         history: [ChatMessage]? = nil, user: AIUserProfile? = nil) -> ChatReplyRequest {
        let message = ChatMessage.user("当前问题", recipients: ["xiaobai"])
        return ChatReplyRequest(conversationID: UUID(), kind: kind, groupName: "朋友",
            members: [.xiaobai], character: .xiaobai, userMessage: message,
            history: (history ?? []) + [message], profile: profile, userProfile: user)
    }
    private func client() -> DeepSeekChatClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatURLProtocol.self]
        return DeepSeekChatClient(session: URLSession(configuration: config))
    }
    override func tearDown() { ChatURLProtocol.respond = nil }

    func testLegacyHistoryWithoutConfigurationOrPartialFlagsStillLoads() throws {
        var history = ChatHistory()
        let id = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: ["xiaobai"])
        _ = try history.enqueue("原有消息", in: id, availableIDs: ["xiaobai"])
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(ChatHistory.self, from: data)
        XCTAssertNil(decoded.configuration)
        XCTAssertNil(decoded.conversations[0].messages[0].interrupted)
        XCTAssertEqual(decoded.conversations[0].messages[0].text, "原有消息")
    }
    func testContextUsesRecentCompleteRoundsAndAlwaysCurrentMessage() throws {
        var old = ChatMessage.user("不该携带的旧内容", recipients: ["xiaobai"]); old.delivery = .sent
        var recent = ChatMessage.user("最近问题", recipients: ["xiaobai"]); recent.delivery = .sent
        let reply = ChatMessage.reply("最近答案", character: .xiaobai, to: recent.id)
        var p = AICharacterProfile(); p.contextRounds = 1
        let output = try AIChatContext.messages(for: request(profile: p, history: [old, recent, reply]))
        XCTAssertEqual(output.dropFirst().map(\.content), ["最近问题", "最近答案", "当前问题"])
        p.contextRounds = 0
        XCTAssertEqual(try AIChatContext.messages(for: request(profile: p, history: [recent, reply])).count, 2)
    }
    func testGroupLabelsOtherMembersAndNeverTreatsThemAsThisAssistant() throws {
        var user = ChatMessage.user("大家好", recipients: ["xiaobai", "other"]); user.delivery = .sent
        let other = ChatMessage(id: UUID(), characterID: "other", senderName: "另一位", text: "别人的回答", createdAt: .now,
            replyToID: user.id, replyCharacterIDs: [], delivery: .sent)
        var partial = ChatMessage.reply("未完成内容", character: .xiaobai, to: user.id); partial.interrupted = true
        let group = try AIChatContext.messages(for: request(kind: .group, history: [user, other, partial]))
        XCTAssertTrue(group.contains(.init(role: "user", content: "[另一位] 别人的回答")))
        XCTAssertFalse(group.contains { $0.content == "未完成内容" })
        let direct = try AIChatContext.messages(for: request(history: [user, other]))
        XCTAssertFalse(direct.contains { $0.content.contains("别人的回答") })
    }
    func testProfileAndUserOptOutBuildIndependentSystemPrompts() throws {
        var p = AICharacterProfile(); p.personality = "爱讲冷笑话"; p.callsUser = "船长"
        var user = AIUserProfile(); user.nickname = "私密昵称"; user.information = "私密资料"; user.shareWithCharacters = false
        var output = try AIChatContext.messages(for: request(profile: p, user: user))[0].content
        XCTAssertTrue(output.contains("爱讲冷笑话")); XCTAssertTrue(output.contains("船长"))
        XCTAssertFalse(output.contains("私密"))
        user.shareWithCharacters = true
        output = try AIChatContext.messages(for: request(profile: p, user: user))[0].content
        XCTAssertTrue(output.contains("私密昵称")); XCTAssertTrue(output.contains("私密资料"))
    }
    func testConfigurationRejectsInvalidLimitsAndHeaderInjection() {
        var p = AICharacterProfile(); p.contextRounds = -1
        XCTAssertThrowsError(try p.validate())
        p = AICharacterProfile(); p.model = "model\nsecret"
        XCTAssertThrowsError(try p.validate())
        p = AICharacterProfile(); p.maxOutputTokens = 0
        XCTAssertThrowsError(try p.validate())
        p = AICharacterProfile(); p.background = String(repeating: "字", count: 4001)
        XCTAssertThrowsError(try p.validate())
        XCTAssertThrowsError(try DeepSeekChatClient.validateKey("sk-test\nInjected: yes"))
        XCTAssertThrowsError(try DeepSeekChatClient.validateKey(""))
    }
    func testRequestUsesOfficialHostAuthorizationAndExplicitThinkingMode() throws {
        var p = AICharacterProfile(); p.model = "deepseek-v4-pro"; p.thinking = true
        let r = try DeepSeekChatClient.request(key: "sk-unit-test-only", chat: request(profile: p))
        XCTAssertEqual(r.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer sk-unit-test-only")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, p.model)
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "enabled")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertFalse(String(data: r.httpBody!, encoding: .utf8)!.contains("sk-unit-test-only"))
    }
    func testSSESupportsKeepaliveUnicodeMultipleLinesAndIgnoresReasoning() throws {
        var s = DeepSeekStream()
        try s.line(": keep-alive"); try s.line("")
        try s.line("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"不落盘的思考\"}}]}"); try s.line("")
        try s.line("data: {\"choices\":"); try s.line("data: [{\"delta\":{\"content\":\"你好🐳\"},\"finish_reason\":\"stop\"}]}"); try s.line("")
        try s.line("data: [DONE]")
        XCTAssertEqual(try s.finish(), "你好🐳")
    }
    func testByteLinesPreserveEmptyEventBoundariesCRLFAndUnicode() throws {
        var decoder = SSELines()
        var lines: [String] = []
        for byte in Data("data: 你好🐳\r\n\r\ndata: next\n\ndata: last\r\rTAIL".utf8) {
            if let line = try decoder.byte(byte) { lines.append(line) }
        }
        if let tail = try decoder.finish() { lines.append(tail) }
        XCTAssertEqual(lines, ["data: 你好🐳", "", "data: next", "", "data: last", "", "TAIL"])
    }
    func testSSERejectsMissingDoneLengthAndServiceErrorsWithoutExposingBody() throws {
        var s = DeepSeekStream()
        try s.line("data: {\"choices\":[{\"delta\":{\"content\":\"部分\"},\"finish_reason\":\"stop\"}]}"); try s.line("")
        XCTAssertThrowsError(try s.finish()); XCTAssertEqual(s.text, "部分")
        var length = DeepSeekStream()
        try length.line("data: {\"choices\":[{\"delta\":{\"content\":\"部分\"},\"finish_reason\":\"length\"}]}"); try length.line("")
        try length.line("data: [DONE]")
        XCTAssertThrowsError(try length.finish()) { XCTAssertTrue($0.localizedDescription.contains("输出上限")) }
        var bad = DeepSeekStream()
        try bad.line("data: {\"error\":{\"message\":\"sk-private-do-not-echo\"}}")
        XCTAssertThrowsError(try bad.line("")) { XCTAssertFalse($0.localizedDescription.contains("sk-private")) }
    }
    func testModelsAreReadFromAPIAndUnknownMetadataIsAllowed() async throws {
        ChatURLProtocol.respond = { request in
            XCTAssertEqual(request.url?.path, "/models")
            return (200, [:], Data(#"{"data":[{"id":"deepseek-flash","name":"Flash","context_window":1000000}]}"#.utf8))
        }
        let models = try await client().models(key: "sk-unit-test-only")
        XCTAssertEqual(models.map(\.id), ["deepseek-flash"])
    }
    func testHTTPAndNetworkErrorsAreSafeAndActionable() async throws {
        for code in [401, 402, 429, 503] {
            ChatURLProtocol.respond = { _ in (code, [:], Data("secret-body-sk-private".utf8)) }
            do { _ = try await client().models(key: "sk-unit-test-only"); XCTFail("Must fail") }
            catch { XCTAssertEqual(error.localizedDescription, AIChatError.http(code).localizedDescription) }
        }
        ChatURLProtocol.respond = { _ in throw URLError(.timedOut) }
        do { _ = try await client().models(key: "sk-unit-test-only"); XCTFail("Must fail") }
        catch { XCTAssertEqual(error.localizedDescription, AIChatError.timeout.localizedDescription) }
    }
    func testStreamingTransportReadsRealSSEWireFormat() async throws {
        ChatURLProtocol.respond = { _ in
            (200, ["Content-Type": "text/event-stream; charset=utf-8"], Data("data: {\"choices\":[{\"delta\":{\"content\":\"真实格式\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8))
        }
        let answer = try await client().reply(key: "sk-unit-test-only", request: request(), onPartial: { _ in })
        XCTAssertEqual(answer, "真实格式")
    }
    func testToolTransportReturnsResultsWithIDsAndTransientThinking() async throws {
        var profile = AICharacterProfile(); profile.appControl = true; profile.thinking = true
        let spy = ToolTransportSpy()
        ChatURLProtocol.respond = { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let payload: [String: Any]
            if messages.last?["role"] as? String == "tool" {
                XCTAssertEqual(messages.last?["tool_call_id"] as? String, "wire-tool-1")
                XCTAssertEqual(messages.last?["content"] as? String, "saved")
                XCTAssertEqual(messages.dropLast().last?["reasoning_content"] as? String, "transient-thought-only")
                payload = ["choices": [["delta": ["content": "已保存。"], "finish_reason": "stop"]]]
            } else {
                XCTAssertNotNil(body["tools"])
                payload = ["choices": [["delta": ["reasoning_content": "transient-thought-only", "tool_calls": [
                    ["index": 0, "id": "wire-tool-1", "type": "function", "function": ["name": "set_artwork", "arguments": "{\"artwork_id\":\"default\"}"]]
                ]], "finish_reason": "tool_calls"]]]
            }
            let event = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            return (200, ["Content-Type": "text/event-stream"], Data(("data: " + event + "\n\ndata: [DONE]\n\n").utf8))
        }
        let answer = try await client().reply(key: "sk-unit-test-only", request: request(profile: profile), onPartial: { _ in }, onTool: { call in
            await spy.record(call); return "saved"
        })
        XCTAssertEqual(answer, "已保存。")
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.function.name, "set_artwork")
        XCTAssertFalse(answer.contains("transient-thought"))
    }
    func testBackupRoundtripIncludesPublicPreferencesAndRejectsCorruption() throws {
        var history = ChatHistory(); history.configuration = AIChatPreferences()
        history.configuration?.characters["xiaobai"] = .standard(for: .xiaobai)
        let data = try JSONEncoder().encode(ChatBackup(history: history))
        XCTAssertEqual(try ChatBackup.decode(data).history, history)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apiKey"))
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        value["version"] = 999
        XCTAssertThrowsError(try ChatBackup.decode(JSONSerialization.data(withJSONObject: value)))
        XCTAssertThrowsError(try ChatBackup.decode(Data("broken".utf8)))
    }
}

#if canImport(Combine)
private actor PartialChatProvider: ChatReplyProvider {
    var pause = true
    func resume() { pause = false }
    func reply(to request: ChatReplyRequest) async throws -> String { "完整回复" }
    func reply(to request: ChatReplyRequest, onPartial: @escaping @Sendable (String) async -> Void) async throws -> String {
        await onPartial("已经收到的部分")
        if pause { try await Task.sleep(nanoseconds: 5_000_000_000) }
        try Task.checkCancellation()
        return "完整回复"
    }
}

@MainActor final class AIChatStoreTests: XCTestCase {
    private var directory: URL!
    private var file: ChatHistoryFile { .init(url: directory.appendingPathComponent("Chat/history.json")) }
    override func setUp() async throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Chat task did not reach expected state")
    }
    func testStopPreservesPartialAndRetryReplacesItWithoutDuplicate() async throws {
        let provider = PartialChatProvider()
        let store = ChatStore(characters: [.xiaobai], file: file, provider: provider)
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.send("你好", in: id))
        try await wait { store.streaming[id]?.text.isEmpty == false }
        XCTAssertThrowsError(try store.exportBackup())
        store.stop(id)
        try await wait { store.replyingIDs.isEmpty }
        let chat = try XCTUnwrap(store.conversation(id))
        XCTAssertEqual(chat.messages.last?.text, "已经收到的部分")
        XCTAssertEqual(chat.messages.last?.interrupted, true)
        XCTAssertEqual(chat.messages.first?.delivery, .failed)
        XCTAssertEqual(try file.load(), store.history)
        await provider.resume()
        store.retry(in: id, messageID: chat.messages[0].id)
        try await wait { store.replyingIDs.isEmpty }
        XCTAssertEqual(store.conversation(id)?.messages.count, 2)
        XCTAssertEqual(store.conversation(id)?.messages.last?.text, "完整回复")
        XCTAssertEqual(store.conversation(id)?.messages.first?.delivery, .sent)
    }
    func testSettingsAndBackupPersistAndInvalidImportLeavesOriginalUntouched() throws {
        let store = ChatStore(characters: [.xiaobai], file: file)
        var config = store.configuration
        config.characters["xiaobai"] = .standard(for: .xiaobai)
        config.characters["xiaobai"]?.thinking = true
        config.user.nickname = "船长"
        XCTAssertTrue(store.saveConfiguration(config))
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        store.setDraft("草稿", in: id)
        let backup = try store.exportBackup()
        XCTAssertFalse(store.importBackup(Data("bad".utf8)))
        XCTAssertEqual(store.configuration, config)
        store.delete(id)
        XCTAssertTrue(store.importBackup(backup))
        let restored = ChatStore(characters: [.xiaobai], file: file)
        XCTAssertEqual(restored.configuration, config)
        XCTAssertEqual(restored.conversation(id)?.draft, "草稿")
        XCTAssertEqual(try file.url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    func testProductionDefaultFailsWithoutKeyRatherThanReturningTestReply() async throws {
        let store = ChatStore(characters: [.xiaobai], file: file)
        let id = try XCTUnwrap(store.create(kind: .direct, characterIDs: ["xiaobai"]))
        XCTAssertTrue(store.send("你好", in: id))
        try await wait { store.replyingIDs.isEmpty }
        XCTAssertEqual(store.conversation(id)?.messages.count, 1)
        XCTAssertEqual(store.error, AIChatError.missingKey.localizedDescription)
    }
    func testOversizedBackupCannotBeExportedAsAnUnrestorableFile() throws {
        var history = ChatHistory()
        let id = try history.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: ["xiaobai"])
        var user = try history.enqueue("保留原始数据", in: id, availableIDs: ["xiaobai"])
        user.delivery = .sent
        history.conversations[0].messages = [user, .reply(String(repeating: "x", count: ChatBackup.maximumSize), character: .xiaobai, to: user.id)]
        try file.save(history)
        let store = ChatStore(characters: [.xiaobai], file: file)
        XCTAssertTrue(store.ready)
        XCTAssertThrowsError(try store.exportBackup()) { XCTAssertEqual($0.localizedDescription, AIChatError.backupTooLarge.localizedDescription) }
        XCTAssertEqual(store.history, history)
        XCTAssertThrowsError(try ChatBackup.decode(Data(count: ChatBackup.maximumSize + 1)))
        XCTAssertEqual(try file.load(), history)
    }
}
#endif

private actor ToolTransportSpy {
    var calls: [ChatToolCall] = []
    func record(_ call: ChatToolCall) { calls.append(call) }
}
