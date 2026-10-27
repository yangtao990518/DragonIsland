import Foundation

struct CharacterVoice: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let characterID: String
    let title: String
    let text: String
    let file: String
    let duration: Double
}

enum VoiceCatalog {
    static func load(bundle: Bundle = .main) -> [CharacterVoice] {
        guard let url = bundle.url(forResource: "Voices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let voices = try? JSONDecoder().decode([CharacterVoice].self, from: data) else { return [] }
        return voices
    }

    static func voices(for characterID: String, in voices: [CharacterVoice]) -> [CharacterVoice] {
        voices.filter { $0.characterID == characterID }
    }
}

struct CharacterVoicePreference: Codable, Equatable {
    var enabled = false
    var voiceID: String?
}

struct CharacterAlarm: Codable, Equatable, Identifiable {
    /// A real system tone, independent of character recordings or voice IDs.
    static let systemSoundID = "system-default"
    enum Backend: String, Codable { case alarmKit, notification }
    let id: UUID
    let characterID: String
    let voiceID: String
    let title: String
    let date: Date
    var backend: Backend = .notification
    var sessionID: UUID?
    var usesSystemSound: Bool { voiceID == Self.systemSoundID }

    var notificationID: String { Self.notificationID(id) }
    static func notificationID(_ id: UUID) -> String { "maiverse.alarm.\(id.uuidString)" }

    static func countdownDate(minutes: Int, now: Date = Date()) -> Date? {
        guard (1...1440).contains(minutes) else { return nil }
        return now.addingTimeInterval(Double(minutes) * 60)
    }

    /// Selecting a clock time always means its next occurrence, including tomorrow.
    static func nextDate(hour: Int, minute: Int, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}

struct CharacterAlarmSnapshot: Codable, Equatable {
    static let storageKey = "characterAlarms.v1"
    var preferences: [String: CharacterVoicePreference] = [:]
    var alarms: [CharacterAlarm] = []

    /// Preserve alarms created while an asynchronous system query was in flight.
    mutating func reconcile(inspectedIDs: Set<UUID>, systemAlarmIDs: Set<UUID>, notificationIDs: Set<String>) {
        alarms.removeAll {
            guard inspectedIDs.contains($0.id) else { return false }
            return $0.backend == .alarmKit ? !systemAlarmIDs.contains($0.id) : !notificationIDs.contains($0.notificationID)
        }
    }

    static func load(defaults: UserDefaults = .standard) -> CharacterAlarmSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

