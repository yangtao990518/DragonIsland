import Foundation
import XCTest
@testable import DragonDomain

final class CharacterAlarmTests: XCTestCase {
    func testCountdownUsesExactEndDateAndRejectsInvalidDurations() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(CharacterAlarm.countdownDate(minutes: 25, now: now), now.addingTimeInterval(1500))
        XCTAssertNil(CharacterAlarm.countdownDate(minutes: 0, now: now))
        XCTAssertNil(CharacterAlarm.countdownDate(minutes: 1441, now: now))
    }

    func testClockTimeSchedulesTomorrowWhenAlreadyPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 8)))
        let next = try XCTUnwrap(CharacterAlarm.nextDate(hour: 7, minute: 30, now: now, calendar: calendar))
        let parts = calendar.dateComponents([.day, .hour, .minute], from: next)
        XCTAssertEqual(parts.day, 27)
        XCTAssertEqual(parts.hour, 7)
        XCTAssertEqual(parts.minute, 30)
        XCTAssertNil(CharacterAlarm.nextDate(hour: 24, minute: 0, now: now, calendar: calendar))
    }

    func testDaylightSavingGapFindsNextValidTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0)))
        let next = try XCTUnwrap(CharacterAlarm.nextDate(hour: 2, minute: 30, now: now, calendar: calendar))
        XCTAssertGreaterThan(next, now)
        XCTAssertEqual(calendar.component(.day, from: next), 8)
        XCTAssertEqual(calendar.component(.hour, from: next), 3)
    }

    func testEachCharacterHasIndependentVoicePreferenceAndPersistence() throws {
        let name = "CharacterAlarmTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var snapshot = CharacterAlarmSnapshot()
        snapshot.preferences["xiaobai"] = CharacterVoicePreference(enabled: true, voiceID: "xiaobai-03")
        snapshot.preferences["future"] = CharacterVoicePreference(enabled: false, voiceID: "future-01")
        snapshot.save(defaults: defaults)
        XCTAssertEqual(CharacterAlarmSnapshot.load(defaults: defaults), snapshot)
        XCTAssertEqual(snapshot.preferences["xiaobai"]?.voiceID, "xiaobai-03")
        XCTAssertFalse(snapshot.preferences["future"]!.enabled)
    }

    func testVoiceFilteringNeverBorrowsAnotherCharactersVoice() {
        let voice = CharacterVoice(id: "xiaobai-01", characterID: "xiaobai", title: "早安", text: "早安", file: "01.wav", duration: 4)
        XCTAssertEqual(VoiceCatalog.voices(for: "xiaobai", in: [voice]), [voice])
        XCTAssertTrue(VoiceCatalog.voices(for: "future", in: [voice]).isEmpty)
    }

    func testAlarmRoundTripRetainsBackendAndSessionCancellationID() throws {
        let id = UUID()
        let alarm = CharacterAlarm(id: id, characterID: "xiaobai", voiceID: "xiaobai-01", title: "陪伴结束",
            date: Date(timeIntervalSince1970: 1000), backend: .alarmKit, sessionID: id)
        let decoded = try JSONDecoder().decode(CharacterAlarm.self, from: JSONEncoder().encode(alarm))
        XCTAssertEqual(decoded, alarm)
        XCTAssertEqual(decoded.notificationID, "maiverse.alarm.\(id.uuidString)")
    }

    func testStaleSystemQueryCannotEraseNewlyScheduledAlarm() {
        let old = CharacterAlarm(id: UUID(), characterID: "xiaobai", voiceID: "xiaobai-01", title: "old", date: .now)
        let new = CharacterAlarm(id: UUID(), characterID: "xiaobai", voiceID: "xiaobai-02", title: "new", date: .now)
        var snapshot = CharacterAlarmSnapshot(alarms: [old, new])
        snapshot.reconcile(inspectedIDs: [old.id], systemAlarmIDs: [], notificationIDs: [])
        XCTAssertEqual(snapshot.alarms, [new])
    }

    func testReconciliationKeepsPendingAndDeliveredNotificationsAndActiveSystemAlarms() {
        let native = CharacterAlarm(id: UUID(), characterID: "xiaobai", voiceID: "01", title: "native", date: .now, backend: .alarmKit)
        let legacy = CharacterAlarm(id: UUID(), characterID: "xiaobai", voiceID: "02", title: "notification", date: .now)
        var snapshot = CharacterAlarmSnapshot(alarms: [native, legacy])
        snapshot.reconcile(inspectedIDs: [native.id, legacy.id], systemAlarmIDs: [native.id], notificationIDs: [legacy.notificationID])
        XCTAssertEqual(snapshot.alarms, [native, legacy])
        snapshot.reconcile(inspectedIDs: [native.id, legacy.id], systemAlarmIDs: [], notificationIDs: [])
        XCTAssertTrue(snapshot.alarms.isEmpty)
    }
}
