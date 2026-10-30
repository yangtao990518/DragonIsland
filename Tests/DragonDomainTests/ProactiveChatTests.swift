import Foundation
import XCTest
@testable import DragonDomain

final class ProactiveChatTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func history() -> ChatHistory {
        var history = ChatHistory()
        var state = ProactiveChatState()
        state.settings.enabled = true
        state.settings.characters["xiaobai"] = ProactiveCharacterSettings(enabled: true)
        history.proactive = state
        return history
    }

    func testDefaultWindowAllowsTenAndExcludesEighteenAndOvernight() {
        let window = ProactiveChatWindow()
        for hour in [0, 8, 9, 18, 21, 23] { XCTAssertFalse(window.allows(date(String(format: "2026-10-31T%02d:00:00Z", hour)), calendar: calendar)) }
        for hour in [10, 12, 17] { XCTAssertTrue(window.allows(date(String(format: "2026-10-31T%02d:00:00Z", hour)), calendar: calendar)) }
    }
    func testAfterQuietTimePlansTheFollowingAllowedWindow() throws {
        let interval = try XCTUnwrap(ProactiveChatWindow().nextInterval(after: date("2026-10-31T18:00:00Z"), calendar: calendar))
        XCTAssertEqual(interval.start, date("2026-11-01T10:00:00Z"))
        XCTAssertEqual(interval.end, date("2026-11-01T18:00:00Z"))
    }
    func testNearClosingTimeDoesNotRushARequestOrSendOutsideWindow() throws {
        let interval = try XCTUnwrap(ProactiveChatWindow().nextInterval(after: date("2026-10-31T17:58:00Z"), calendar: calendar))
        XCTAssertEqual(interval.start, date("2026-11-01T10:00:00Z"))
    }
    func testOvernightWindowIsResolvedAcrossTheCorrectDay() throws {
        let window = ProactiveChatWindow(startMinute: 22 * 60, endMinute: 8 * 60)
        let interval = try XCTUnwrap(window.nextInterval(after: date("2026-10-31T01:00:00Z"), calendar: calendar))
        XCTAssertEqual(interval.start, date("2026-10-30T22:00:00Z"))
        XCTAssertEqual(interval.end, date("2026-10-31T08:00:00Z"))
        XCTAssertTrue(window.allows(date("2026-10-31T01:00:00Z"), calendar: calendar))
        XCTAssertFalse(window.allows(interval.end, calendar: calendar))
    }
    func testInvalidWindowsAndExcessiveFrequencyAreRejected() {
        XCTAssertThrowsError(try ProactiveChatWindow(startMinute: 0, endMinute: 0).validate())
        XCTAssertThrowsError(try ProactiveChatWindow(startMinute: -1, endMinute: 600).validate())
        var settings = ProactiveChatSettings(); settings.dailyCount = 4
        XCTAssertThrowsError(try settings.validate())
    }
    func testRandomTimesStayWithinWindowAndNeverEqualItsEnd() throws {
        var value = history(); value.proactive?.settings.dailyCount = 3
        _ = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: { 1 })
        let slots = try XCTUnwrap(value.proactive?.slots)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(Set(slots.map(\.scheduledAt)).count, 3)
        for slot in slots {
            XCTAssertTrue(value.proactive!.settings.window.allows(slot.scheduledAt, calendar: calendar))
            XCTAssertLessThan(slot.scheduledAt, date("2026-10-31T18:00:00Z"))
        }
    }
    func testPlanningTwiceDoesNotGenerateDuplicateQuotaOrPrivateChats() throws {
        var value = history()
        let first = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: { 0.5 })
        let second = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:05:00Z"), calendar: calendar)
        XCTAssertEqual(first.count, 1); XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(value.conversations.count, 1)
        XCTAssertTrue(value.conversations[0].messages.isEmpty, "Planning must not fabricate messages")
    }
    func testFailedPreparationStillConsumesTheReservedQuota() throws {
        var value = history()
        _ = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar)
        value.proactive?.slots[0].status = .failed
        let retry = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:10:00Z"), calendar: calendar)
        XCTAssertTrue(retry.isEmpty)
    }
    func testOnlyPreparedMessagesAreDeliveredAndDeliveryIsIdempotent() throws {
        var value = history()
        _ = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: { 0.5 })
        let slot = try XCTUnwrap(value.proactive?.slots.first)
        XCTAssertTrue(try value.deliverProactiveChats(now: slot.scheduledAt).isEmpty)
        value.proactive?.slots[0].status = .ready; value.proactive?.slots[0].text = "想来问问你今天过得怎么样。"
        XCTAssertTrue(try value.deliverProactiveChats(now: slot.scheduledAt.addingTimeInterval(-1)).isEmpty)
        XCTAssertEqual(try value.deliverProactiveChats(now: slot.scheduledAt), [slot.id])
        XCTAssertTrue(try value.deliverProactiveChats(now: slot.scheduledAt.addingTimeInterval(1)).isEmpty)
        let message = try XCTUnwrap(value.conversations[0].messages.first)
        XCTAssertEqual(message.id, slot.id); XCTAssertEqual(message.isProactive, true)
        XCTAssertFalse(message.isUser); XCTAssertNil(message.replyToID)
        XCTAssertEqual(value.conversations[0].messages.count, 1)
        XCTAssertNoThrow(try value.validate())
    }
    func testDisablingCancelsReadyMessageInsteadOfDeliveringIt() throws {
        var value = history()
        _ = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar)
        value.proactive?.slots[0].status = .ready; value.proactive?.slots[0].text = "你好"
        value.proactive?.settings.enabled = false
        XCTAssertTrue(try value.deliverProactiveChats(now: date("2026-11-01T00:00:00Z")).isEmpty)
        XCTAssertEqual(value.proactive?.slots.first?.status, .cancelled)
        XCTAssertTrue(value.conversations[0].messages.isEmpty)
    }
    func testUnrelatedGroupIsNeverSelected() throws {
        var value = history()
        value.proactive?.settings.characters["xiaobai"] = ProactiveCharacterSettings(enabled: true, destination: .group, groupID: UUID())
        XCTAssertTrue(try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar).isEmpty)
        XCTAssertTrue(value.conversations.isEmpty)
    }
    func testLegacyMessagesCannotPretendToBeUnparentedAssistantReplies() throws {
        var value = history()
        _ = try value.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar)
        value.conversations[0].messages = [.init(id: UUID(), characterID: "xiaobai", senderName: "小白", text: "不合法",
            createdAt: .now, replyToID: nil, replyCharacterIDs: [], delivery: .sent)]
        XCTAssertThrowsError(try value.validate())
    }
    func testDeepLinkRoundTripRejectsUnrelatedRoutes() {
        let id = UUID()
        XCTAssertEqual(ChatDeepLink.conversationID(ChatDeepLink.url(id)), id)
        XCTAssertNil(ChatDeepLink.conversationID(URL(string: "https://chat/\(id)")!))
        XCTAssertNil(ChatDeepLink.conversationID(URL(string: "dragonisle://chat/not-an-id")!))
        XCTAssertNil(ChatDeepLink.conversationID(URL(string: "dragonisle://chat/extra/\(id)")!))
    }
    func testDaylightSavingWindowUsesWallClockAndPreservesAllowedHours() throws {
        var local = calendar; local.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let interval = try XCTUnwrap(ProactiveChatWindow().nextInterval(after: date("2026-03-29T00:30:00Z"), calendar: local))
        XCTAssertEqual(local.component(.hour, from: interval.start), 10)
        XCTAssertEqual(local.component(.hour, from: interval.end), 18)
    }
    func testProactiveContextNeverEnablesToolsAndIncludesPriorRealProactiveMessages() throws {
        let prior = ChatMessage(id: UUID(), characterID: "xiaobai", senderName: "小白", text: "上次的主动问候",
            createdAt: date("2026-10-31T10:00:00Z"), replyToID: nil, replyCharacterIDs: [], delivery: .sent, isProactive: true)
        var profile = AICharacterProfile.standard(for: .xiaobai); profile.appControl = true; profile.automaticStickers = true
        let instruction = ChatMessage.user("内部准备指令", recipients: ["xiaobai"])
        var request = ChatReplyRequest(conversationID: UUID(), kind: .direct, groupName: "", members: [.xiaobai],
            character: .xiaobai, userMessage: instruction, history: [prior], profile: profile)
        request.proactiveDeliveryDate = date("2026-11-01T11:00:00Z")
        XCTAssertTrue(ChatTools.allowed(for: request).isEmpty)
        let messages = try AIChatContext.messages(for: request)
        XCTAssertTrue(messages[0].content.contains("没有新的用户发言"))
        XCTAssertTrue(messages.contains { $0.role == "assistant" && $0.content == prior.text })
        XCTAssertFalse(messages[0].content.contains("可用表情："))
        request.profile?.contextRounds = 0
        XCTAssertFalse(try AIChatContext.messages(for: request).contains { $0.content == prior.text })
    }
}

private actor ProactiveTestProvider: ChatReplyProvider {
    private(set) var requests: [ChatReplyRequest] = []
    let failing: Bool
    init(failing: Bool = false) { self.failing = failing }
    func reply(to request: ChatReplyRequest) async throws -> String {
        requests.append(request)
        if failing { throw AIChatError.missingKey }
        return "想来问问你今天过得怎么样。"
    }
}

@MainActor
final class ProactiveChatStoreTests: XCTestCase {
    private func store(provider: any ChatReplyProvider = ProactiveTestProvider()) -> (ChatStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")), provider: provider), root)
    }
    private func enable(_ store: ChatStore, group: UUID? = nil) {
        var settings = ProactiveChatSettings(); settings.enabled = true
        settings.characters["xiaobai"] = .init(enabled: true, destination: group == nil ? .direct : .group, groupID: group)
        XCTAssertTrue(store.saveProactiveSettings(settings))
    }
    func testPreparingUsesRealProviderButAddsNoFakeUserMessage() async throws {
        let provider = ProactiveTestProvider()
        let (store, root) = store(provider: provider)
        defer { try? FileManager.default.removeItem(at: root) }
        var preferences = store.configuration
        var profile = preferences.profile(for: .xiaobai); profile.appControl = true; profile.automaticStickers = true
        preferences.characters["xiaobai"] = profile; XCTAssertTrue(store.saveConfiguration(preferences))
        enable(store)
        let id = try XCTUnwrap(store.planProactiveChats().first)
        try await store.prepareProactiveChat(id)
        let requests = await provider.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertNotNil(request.proactiveDeliveryDate)
        XCTAssertEqual(request.profile?.appControl, false); XCTAssertEqual(request.profile?.automaticStickers, false)
        XCTAssertEqual(store.configuration.profile(for: .xiaobai).appControl, true)
        XCTAssertTrue(ChatTools.allowed(for: request).isEmpty)
        XCTAssertTrue(store.conversations.allSatisfy { $0.messages.isEmpty })
        XCTAssertEqual(store.proactiveState.slots.first?.status, .ready)
    }
    func testPreparedGroupMessageMentionsUserAndRestoresWithoutDuplicates() async throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = try XCTUnwrap(store.create(kind: .group, name: "测试群", characterIDs: ["xiaobai"]))
        var preferences = store.configuration; preferences.user.nickname = "阿桃"; XCTAssertTrue(store.saveConfiguration(preferences))
        enable(store, group: group)
        let id = try XCTUnwrap(store.planProactiveChats().first)
        try await store.prepareProactiveChat(id)
        let slot = try XCTUnwrap(store.proactiveState.slots.first)
        let restarted = ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")))
        XCTAssertEqual(restarted.deliverProactiveChats(now: slot.scheduledAt), [id])
        XCTAssertTrue(restarted.deliverProactiveChats(now: slot.scheduledAt).isEmpty)
        let message = try XCTUnwrap(restarted.conversation(group)?.messages.last)
        XCTAssertTrue(message.text.hasPrefix("@阿桃 ")); XCTAssertEqual(message.mentionsUser, true)
        XCTAssertEqual(restarted.conversation(group)?.unreadProactiveCount, 1)
        restarted.markRead(group, now: slot.scheduledAt.addingTimeInterval(1))
        XCTAssertEqual(restarted.conversation(group)?.unreadProactiveCount, 0)
        XCTAssertNoThrow(try restarted.history.validate())
    }
    func testInterruptedPlanRestartsAsFailedAndDoesNotClaimToHaveSent() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        enable(store); _ = store.planProactiveChats()
        let restarted = ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")))
        XCTAssertEqual(restarted.proactiveState.slots.first?.status, .failed)
        XCTAssertTrue(restarted.conversations.allSatisfy { $0.messages.isEmpty })
        XCTAssertTrue(restarted.planProactiveChats().isEmpty)
    }
    func testFailedPreparationDoesNotContinuouslyRetryOnReopen() async throws {
        let provider = ProactiveTestProvider(failing: true)
        let (store, root) = store(provider: provider)
        defer { try? FileManager.default.removeItem(at: root) }
        enable(store); let id = try XCTUnwrap(store.planProactiveChats().first)
        do { try await store.prepareProactiveChat(id); XCTFail("Expected missing key") } catch { }
        XCTAssertEqual(store.proactiveState.slots.first?.status, .failed)
        XCTAssertTrue(store.planProactiveChats().isEmpty)
        let count = await provider.requests.count
        XCTAssertEqual(count, 1)
    }
    func testChangingWindowCancelsOldQueuedMessagesAndAllowsTurningOffAfterGroupDeletion() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = try XCTUnwrap(store.create(kind: .group, name: "群", characterIDs: ["xiaobai"]))
        enable(store, group: group); _ = store.planProactiveChats()
        var settings = store.proactiveState.settings; settings.window.endMinute = 17 * 60
        XCTAssertTrue(store.saveProactiveSettings(settings))
        XCTAssertTrue(store.proactiveState.slots.allSatisfy { $0.status == .cancelled })
        store.delete(group)
        settings.enabled = false
        XCTAssertTrue(store.saveProactiveSettings(settings), "Turning off must work even if a selected group no longer exists")
    }
    func testPreparedQueueAndSettingsSurviveMediaCompatibleBackup() async throws {
        let (store, root) = store()
        let (restored, other) = self.store()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
        enable(store); let id = try XCTUnwrap(store.planProactiveChats().first)
        try await store.prepareProactiveChat(id)
        XCTAssertTrue(restored.importBackup(try store.exportBackup()))
        XCTAssertEqual(restored.proactiveState, store.proactiveState)
        XCTAssertTrue(restored.conversations.allSatisfy { $0.messages.isEmpty })
    }
    func testBuiltinStickersAreOwnedReadOnlyAndUnusedPackDoesNotEnterBackup() throws {
        let bytes = try ChatMediaToolTests.image(gif: false)
        let asset = try ChatMediaAsset.inspect(bytes)
        let builtin = CharacterSticker(id: UUID(), characterID: "xiaobai", name: "认真", meaning: "认真倾听", asset: asset)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")), builtinStickers: [builtin])
        XCTAssertEqual(store.stickers(for: "xiaobai"), [builtin])
        XCTAssertTrue(store.stickers(for: "dafeiyu").isEmpty)
        store.removeSticker(builtin.id)
        XCTAssertFalse(store.editSticker(builtin.id, name: "改名", meaning: "改名"))
        XCTAssertEqual(store.stickers(for: "xiaobai"), [builtin])
        let backup = try ChatBackup.decode(store.exportBackup())
        XCTAssertTrue(backup.history.mediaAssets.isEmpty)
        XCTAssertTrue(backup.media?.isEmpty == true)
    }
}
