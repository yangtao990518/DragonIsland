import XCTest
@testable import DragonDomain

final class ProactiveIntervalTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var fish: CompanionCharacter {
        .init(id: "dafeiyu", name: "大肥鱼", subtitle: "鲸鱼", introduction: "你好", origin: "测试", chibiAsset: "Fish", portraitAsset: "Fish", heroAsset: "Fish", chibiSource: "fish.png", standingSource: "fish.png")
    }
    private func history(minutes: Int = 60) -> ChatHistory {
        var h = ChatHistory(); var state = ProactiveChatState(); state.settings.enabled = true
        state.settings.characters["xiaobai"] = .init(enabled: true, window: .init(), intervalMinutes: minutes)
        h.proactive = state; return h
    }
    func testRandomMessagesRespectMinimumGapAndQuietHoursWithoutBecomingPeriodic() throws {
        var h = history(); var index = 0
        let units = [0.1, 0.8, 0.3, 0.9]
        _ = try h.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: {
            defer { index += 1 }; return units[index % units.count]
        })
        let times = try XCTUnwrap(h.proactive?.slots.map(\.scheduledAt).sorted())
        XCTAssertGreaterThan(times.count, 2)
        let gaps = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }
        XCTAssertTrue(gaps.allSatisfy { $0 >= 3600 })
        XCTAssertGreaterThan(Set(gaps).count, 1, "Minimum interval must not turn random chat into a periodic alarm")
        XCTAssertTrue(times.allSatisfy { ProactiveChatWindow().allows($0, calendar: calendar) })
        XCTAssertTrue(try h.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:01:00Z"), calendar: calendar, randomUnit: { 0 }).isEmpty)
        XCTAssertNoThrow(try h.validate())
    }
    func testEachRoleUsesItsOwnWindowAndMinimumInterval() throws {
        var h = history(minutes: 30)
        h.proactive?.settings.characters["xiaobai"]?.window = .init(startMinute: 600, endMinute: 720)
        h.proactive?.settings.characters[fish.id] = .init(enabled: true, window: .init(startMinute: 840, endMinute: 1080), intervalMinutes: 90)
        _ = try h.planProactiveChats(characters: [.xiaobai, fish], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: { 0.2 })
        for (id, minimum) in [("xiaobai", 30), ("dafeiyu", 90)] {
            let slots = h.proactive!.slots.filter { $0.characterID == id }.sorted { $0.scheduledAt < $1.scheduledAt }
            XCTAssertFalse(slots.isEmpty)
            let window = h.proactive!.settings.preference(for: id).window!
            XCTAssertTrue(slots.allSatisfy { window.allows($0.scheduledAt, calendar: calendar) })
            XCTAssertTrue(zip(slots, slots.dropFirst()).allSatisfy { $1.scheduledAt.timeIntervalSince($0.scheduledAt) >= Double(minimum * 60) })
        }
    }
    func testHighFrequencyQueueIsBoundedAndSharedFairlyAcrossRoles() throws {
        var h = history(minutes: 15)
        h.proactive?.settings.characters[fish.id] = .init(enabled: true, window: .init(), intervalMinutes: 15)
        _ = try h.planProactiveChats(characters: [.xiaobai, fish], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: { 0 })
        XCTAssertEqual(h.proactive?.slots.count, 32)
        XCTAssertEqual(h.proactive?.slots.filter { $0.characterID == "xiaobai" }.count, 16)
        XCTAssertEqual(h.proactive?.slots.filter { $0.characterID == fish.id }.count, 16)
        h.proactive?.slots[0].status = .failed; h.proactive?.slots[1].status = .failed
        let ids = try h.planProactiveChats(characters: [.xiaobai, fish], now: date("2026-10-31T10:00:00Z"), calendar: calendar, randomUnit: { 0 })
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(h.proactive!.slots.map(\.scheduledAt)).count, 17)
        XCTAssertNoThrow(try h.validate())
    }
    func testMinimumGapSurvivesAChangedPolicyAndDoesNotRepeatFailedRequests() throws {
        var h = history(minutes: 60)
        _ = try h.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: { 0 })
        h.proactive?.slots[0].status = .failed
        XCTAssertTrue(try h.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T10:01:00Z"), calendar: calendar, randomUnit: { 0 }).isEmpty)
        let old = h.proactive!.slots[0].scheduledAt
        for index in h.proactive!.slots.indices.dropFirst() { h.proactive?.slots[index].status = .cancelled }
        h.proactive?.characterPolicies = ["xiaobai": UUID()]
        _ = try h.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T10:01:00Z"), calendar: calendar, randomUnit: { 0 })
        let fresh = h.proactive!.slots.filter { $0.policyID == h.proactive!.policy(for: "xiaobai") }
        XCTAssertTrue(fresh.allSatisfy { $0.scheduledAt.timeIntervalSince(old) >= 3600 })
    }
    func testBuild18SettingsAndSchedulesDecodeWithoutMigrationOrReset() throws {
        var h = history(); h.proactive?.settings.characters["xiaobai"]?.intervalMinutes = nil
        _ = try h.planProactiveChats(characters: [.xiaobai], now: date("2026-10-31T09:00:00Z"), calendar: calendar, randomUnit: { 0.5 })
        let restored = try JSONDecoder().decode(ChatHistory.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(restored, h)
        XCTAssertNil(restored.proactive?.settings.preference(for: "xiaobai").intervalMinutes)
        XCTAssertNil(restored.proactive?.characterPolicies)
        XCTAssertEqual(restored.proactive?.slots.count, 1)
    }
    func testInvalidRoleFrequencyAndRoleWindowAreRejected() {
        var h = history(minutes: 1)
        XCTAssertThrowsError(try h.proactive!.validate())
        h.proactive?.settings.characters["xiaobai"]?.intervalMinutes = 60
        h.proactive?.settings.characters["xiaobai"]?.window = .init(startMinute: 600, endMinute: 600)
        XCTAssertThrowsError(try h.proactive!.validate())
    }
}

@MainActor
final class ProactiveRoleStoreTests: XCTestCase {
    private var fish: CompanionCharacter {
        .init(id: "dafeiyu", name: "大肥鱼", subtitle: "鲸鱼", introduction: "你好", origin: "测试", chibiAsset: "Fish", portraitAsset: "Fish", heroAsset: "Fish", chibiSource: "fish.png", standingSource: "fish.png")
    }
    func testEditingOneRolePreservesOtherRolePolicyAndPendingMessages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(characters: [.xiaobai, fish], file: .init(url: root.appendingPathComponent("history.json")))
        var preference = ProactiveCharacterSettings(enabled: true, window: .init(), intervalMinutes: 60)
        XCTAssertTrue(store.saveProactivePreference(preference, for: "xiaobai"))
        XCTAssertTrue(store.saveProactivePreference(preference, for: fish.id))
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        XCTAssertFalse(store.planProactiveChats(now: morning).isEmpty)
        let previous = store.proactiveState.slots.filter { $0.characterID == fish.id }
        let policy = store.proactiveState.policy(for: fish.id)
        preference.intervalMinutes = 120
        XCTAssertTrue(store.saveProactivePreference(preference, for: "xiaobai"))
        XCTAssertEqual(store.proactiveState.slots.filter { $0.characterID == fish.id }, previous)
        XCTAssertEqual(store.proactiveState.policy(for: fish.id), policy)
        XCTAssertTrue(store.proactiveState.slots.filter { $0.characterID == "xiaobai" }.allSatisfy { $0.status == .cancelled })
    }
    func testFormerMasterOffDoesNotEnableTheOtherRoleWhenOneRoleIsEnabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(characters: [.xiaobai, fish], file: .init(url: root.appendingPathComponent("history.json")))
        var settings = ProactiveChatSettings()
        settings.characters = ["xiaobai": .init(enabled: true), fish.id: .init(enabled: true)]
        XCTAssertTrue(store.saveProactiveSettings(settings))
        XCTAssertTrue(store.saveProactivePreference(.init(enabled: true, intervalMinutes: 60), for: "xiaobai"))
        XCTAssertTrue(store.proactiveState.settings.preference(for: "xiaobai").enabled)
        XCTAssertFalse(store.proactiveState.settings.preference(for: fish.id).enabled)
    }
}
