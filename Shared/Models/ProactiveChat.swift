import Foundation

struct ProactiveChatWindow: Codable, Equatable, Sendable {
    var startMinute = 10 * 60
    var endMinute = 18 * 60

    func validate() throws {
        guard (0..<1440).contains(startMinute), (0..<1440).contains(endMinute), startMinute != endMinute else {
            throw ProactiveChatError.invalidSettings
        }
    }
    func allows(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return startMinute < endMinute ? (startMinute..<endMinute).contains(minute)
            : minute >= startMinute || minute < endMinute
    }

    /// A real wall-clock interval, including overnight windows and DST changes.
    func nextInterval(after now: Date, calendar: Calendar = .current) -> DateInterval? {
        let midnight = calendar.startOfDay(for: now)
        for offset in -1...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: midnight),
                  let endDay = calendar.date(byAdding: .day, value: startMinute < endMinute ? 0 : 1, to: day),
                  let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day),
                  let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: endDay),
                  end.timeIntervalSince(max(start, now)) > 5 * 60 else { continue }
            return DateInterval(start: start, end: end)
        }
        return nil
    }
}

struct ProactiveCharacterSettings: Codable, Equatable, Sendable {
    enum Destination: String, Codable, CaseIterable, Sendable { case direct, group }
    var enabled = false
    var destination = Destination.direct
    var groupID: UUID? = nil
}

struct ProactiveChatSettings: Codable, Equatable, Sendable {
    var enabled = false
    var window = ProactiveChatWindow()
    var dailyCount = 1
    var notifications = true
    var islandReminder = true
    var characters: [String: ProactiveCharacterSettings] = [:]
    func validate() throws {
        try window.validate()
        guard (1...3).contains(dailyCount), characters.count <= 100,
              characters.keys.allSatisfy({ !$0.isEmpty && $0.count <= 120 }),
              characters.values.allSatisfy({ !$0.enabled || $0.destination != .group || $0.groupID != nil }) else {
            throw ProactiveChatError.invalidSettings
        }
    }
}

struct ProactiveChatSlot: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case planned, ready, delivered, failed, cancelled }
    let id: UUID
    let policyID: UUID
    let characterID: String
    let characterName: String
    let conversationID: UUID
    let scheduledAt: Date
    let windowStart: Date
    let timeZoneID: String
    var status: Status = .planned
    var text: String? = nil
    var failure: String? = nil
    var notificationScheduled = false
    var notificationID: String { "maiverse.chat.proactive.\(id.uuidString)" }
}

struct ProactiveChatState: Codable, Equatable, Sendable {
    var settings = ProactiveChatSettings()
    var policyID = UUID()
    var slots: [ProactiveChatSlot] = []
    func validate() throws {
        try settings.validate()
        guard slots.count <= 1000, Set(slots.map(\.id)).count == slots.count else { throw ProactiveChatError.invalidSettings }
        for slot in slots {
            guard !slot.characterID.isEmpty, slot.characterID.count <= 120, !slot.characterName.isEmpty, slot.characterName.count <= 120,
                  TimeZone(identifier: slot.timeZoneID) != nil,
                  slot.scheduledAt.timeIntervalSince1970.isFinite, slot.windowStart.timeIntervalSince1970.isFinite,
                  slot.scheduledAt >= slot.windowStart, slot.scheduledAt.timeIntervalSince(slot.windowStart) < 26 * 3600,
                  (slot.text?.count ?? 0) <= 2000, (slot.failure?.count ?? 0) <= 300,
                  ![.ready, .delivered].contains(slot.status) || !(slot.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProactiveChatError.invalidSettings
            }
            if slot.policyID == policyID, [.planned, .ready].contains(slot.status) {
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: slot.timeZoneID) ?? .current
                guard settings.window.allows(slot.scheduledAt, calendar: calendar) else { throw ProactiveChatError.invalidSettings }
            }
        }
    }
}

enum ProactiveChatError: LocalizedError {
    case invalidSettings, unavailable, expired
    var errorDescription: String? {
        switch self {
        case .invalidSettings: return "请检查主动聊天时段、次数和群聊选择。开始与结束时间不能相同。"
        case .unavailable: return "主动聊天设置或目标会话已改变，这条消息已取消。"
        case .expired: return "已错过这次消息的准备时间，请重新准备下一时段。"
        }
    }
}

extension ChatHistory {
    mutating func recoverInterruptedProactivePlans() {
        guard var state = proactive else { return }
        for index in state.slots.indices where state.slots[index].status == .planned {
            state.slots[index].status = .failed
            state.slots[index].failure = "上次准备被中断，未发送消息。"
        }
        proactive = state
    }
    mutating func cancelProactiveChats(in conversationID: UUID) {
        guard var state = proactive else { return }
        for index in state.slots.indices where state.slots[index].conversationID == conversationID && [.planned, .ready].contains(state.slots[index].status) {
            state.slots[index].status = .cancelled
        }
        proactive = state
    }
    /// Reserve before network calls. Relaunching cannot silently spend the same daily quota again.
    mutating func planProactiveChats(characters: [CompanionCharacter], now: Date = .now,
                                    calendar: Calendar = .current, randomUnit: () -> Double = { Double.random(in: 0..<1) }) throws -> [UUID] {
        var state = proactive ?? ProactiveChatState()
        try state.settings.validate()
        guard state.settings.enabled else { return [] }
        state.slots.removeAll { $0.scheduledAt < now.addingTimeInterval(-8 * 86400) }
        for index in state.slots.indices where [.planned, .ready].contains(state.slots[index].status) {
            if state.slots[index].policyID != state.policyID || state.slots[index].timeZoneID != calendar.timeZone.identifier {
                state.slots[index].status = .cancelled
            }
        }
        guard let interval = state.settings.window.nextInterval(after: now, calendar: calendar) else { return [] }
        let earliest = max(interval.start, now.addingTimeInterval(5 * 60))
        let available = Set(characters.map(\.id))
        var planned: [UUID] = []
        for character in characters {
            let settings = state.settings.characters[character.id] ?? ProactiveCharacterSettings()
            guard settings.enabled else { continue }
            let previous = state.slots.filter {
                $0.policyID == state.policyID && $0.characterID == character.id && $0.windowStart == interval.start
                    && $0.timeZoneID == calendar.timeZone.identifier
            }
            // Failed and cancelled attempts still consume quota for this policy/window.
            let remaining = max(0, state.settings.dailyCount - previous.count)
            guard remaining > 0 else { continue }
            let conversationID: UUID
            if settings.destination == .direct {
                conversationID = try create(kind: .direct, name: "", characterIDs: [character.id], availableIDs: available, now: now)
            } else {
                guard let group = conversations.first(where: { $0.id == settings.groupID && $0.kind == .group && $0.characterIDs.contains(character.id) }) else { continue }
                conversationID = group.id
            }
            for ordinal in 0..<remaining {
                guard state.slots.filter({ [.planned, .ready].contains($0.status) }).count < 32 else { break }
                let slice = interval.end.timeIntervalSince(earliest) / Double(remaining)
                let value = randomUnit()
                guard value.isFinite else { throw ProactiveChatError.invalidSettings }
                let random = min(0.999999, max(0, value))
                let date = earliest.addingTimeInterval((Double(ordinal) + random) * slice)
                guard state.settings.window.allows(date, calendar: calendar) else { continue }
                let slot = ProactiveChatSlot(id: UUID(), policyID: state.policyID, characterID: character.id, characterName: character.name,
                    conversationID: conversationID, scheduledAt: date, windowStart: interval.start, timeZoneID: calendar.timeZone.identifier)
                state.slots.append(slot); planned.append(slot.id)
            }
        }
        proactive = state
        return planned
    }

    /// Materialize only real, prepared messages, atomically with the delivery ledger.
    mutating func deliverProactiveChats(now: Date = .now) throws -> [UUID] {
        guard var state = proactive else { return [] }
        var delivered: [UUID] = []
        for index in state.slots.indices where state.slots[index].status == .ready && state.slots[index].scheduledAt <= now {
            let slot = state.slots[index]
            guard state.settings.enabled, slot.policyID == state.policyID,
                  state.settings.characters[slot.characterID]?.enabled == true,
                  let chat = conversations.firstIndex(where: { $0.id == slot.conversationID && $0.characterIDs.contains(slot.characterID) }),
                  let text = slot.text, !text.isEmpty else { state.slots[index].status = .cancelled; continue }
            if !conversations[chat].messages.contains(where: { $0.id == slot.id }) {
                let reply = ChatMessage(id: slot.id, characterID: slot.characterID, senderName: slot.characterName,
                    text: text, createdAt: slot.scheduledAt, replyToID: nil, replyCharacterIDs: [], delivery: .sent,
                    isProactive: true, mentionsUser: conversations[chat].kind == .group)
                conversations[chat].messages.append(reply)
                conversations[chat].messages.sort { $0.createdAt < $1.createdAt }
                conversations[chat].updatedAt = max(conversations[chat].updatedAt, slot.scheduledAt)
                delivered.append(slot.id)
            }
            state.slots[index].status = .delivered
        }
        proactive = state
        return delivered
    }
}
