import Foundation
import XCTest
@testable import DragonDomain

@MainActor
final class ProactiveSettingsValidationTests: XCTestCase {
    private func make() -> (ChatStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json"))), root)
    }

    func testGroupWithoutSelectionHasSpecificErrorAndLeavesSavedPreferenceIntact() throws {
        let (store, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = ProactiveCharacterSettings(enabled: true, window: .init(), intervalMinutes: 60)
        XCTAssertTrue(store.saveProactivePreference(saved, for: "xiaobai"))
        let original = store.proactiveState
        var draft = saved; draft.destination = .group
        XCTAssertFalse(store.saveProactivePreference(draft, for: "xiaobai"))
        XCTAssertEqual(store.error, ProactiveChatError.missingGroup.localizedDescription)
        XCTAssertFalse(store.error?.contains("开始与结束") ?? true)
        XCTAssertEqual(store.proactiveState, original)
    }

    func testSelectedMemberGroupWithFifteenMinuteIntervalSavesAndSurvivesReopen() throws {
        let (store, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = try XCTUnwrap(store.create(kind: .group, name: "Ai", characterIDs: ["xiaobai"]))
        let preference = ProactiveCharacterSettings(enabled: true, destination: .group, groupID: group,
            window: .init(startMinute: 600, endMinute: 1080), intervalMinutes: 15,
            notifications: true, islandReminder: true)
        XCTAssertTrue(store.saveProactivePreference(preference, for: "xiaobai"), store.error ?? "")
        let reopened = ChatStore(characters: [.xiaobai], file: .init(url: root.appendingPathComponent("history.json")))
        XCTAssertTrue(reopened.ready)
        XCTAssertEqual(reopened.proactiveState.settings.preference(for: "xiaobai"), preference)
    }

    func testDeletedGroupReportsAffectedRoleAndCanBeReplacedWithoutLosingSettings() throws {
        let (store, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = try XCTUnwrap(store.create(kind: .group, name: "旧群", characterIDs: ["xiaobai"]))
        var preference = ProactiveCharacterSettings(enabled: true, destination: .group, groupID: group, window: .init(), intervalMinutes: 15)
        XCTAssertTrue(store.saveProactivePreference(preference, for: "xiaobai"))
        store.delete(group)
        XCTAssertFalse(store.saveProactivePreference(preference, for: "xiaobai"))
        XCTAssertEqual(store.error, ProactiveChatError.invalidGroup(CompanionCharacter.xiaobai.name).localizedDescription)
        let replacement = try XCTUnwrap(store.create(kind: .group, name: "新群", characterIDs: ["xiaobai"]))
        preference.groupID = replacement
        XCTAssertTrue(store.saveProactivePreference(preference, for: "xiaobai"))
        XCTAssertEqual(store.proactiveState.settings.preference(for: "xiaobai").groupID, replacement)
    }

    func testWindowAndIntervalErrorsAreDistinctAndDisabledGroupCanBeSaved() throws {
        var preference = ProactiveCharacterSettings(enabled: true, window: .init(startMinute: 600, endMinute: 600), intervalMinutes: 15)
        XCTAssertThrowsError(try preference.validate()) { error in
            XCTAssertEqual(error.localizedDescription, ProactiveChatError.invalidWindow.localizedDescription)
        }
        preference.window = .init(); preference.intervalMinutes = 1
        XCTAssertThrowsError(try preference.validate()) { error in
            XCTAssertEqual(error.localizedDescription, ProactiveChatError.invalidInterval.localizedDescription)
        }
        preference.enabled = false; preference.intervalMinutes = 15; preference.destination = .group
        XCTAssertNoThrow(try preference.validate())
        let (store, root) = make()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(store.saveProactivePreference(preference, for: "xiaobai"))
        XCTAssertFalse(store.proactiveState.settings.enabled)
    }
}
