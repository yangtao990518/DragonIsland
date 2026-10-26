import ActivityKit
import AppIntents
import Foundation

struct GreetDragonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "和龙娘打招呼"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "活动标识") var sessionID: String

    init() {}
    init(sessionID: String) { self.sessionID = sessionID }

    func perform() async throws -> some IntentResult {
        guard let activity = Activity<DragonAttributes>.activities.first(where: { $0.attributes.sessionID.uuidString == sessionID }) else {
            return .result()
        }
        var state = activity.content.state
        guard !state.hasExpired() else {
            await activity.end(activity.content, dismissalPolicy: .immediate)
            return .result()
        }
        state.greet()
        await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
        return .result()
    }
}

struct ChangeDragonMoodIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "切换龙娘心情"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "活动标识") var sessionID: String

    init() {}
    init(sessionID: String) { self.sessionID = sessionID }

    func perform() async throws -> some IntentResult {
        guard let activity = Activity<DragonAttributes>.activities.first(where: { $0.attributes.sessionID.uuidString == sessionID }) else {
            return .result()
        }
        var state = activity.content.state
        guard !state.hasExpired() else {
            await activity.end(activity.content, dismissalPolicy: .immediate)
            return .result()
        }
        state.cycleMood()
        await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
        return .result()
    }
}

struct EndDragonSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "结束龙娘陪伴"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "活动标识") var sessionID: String

    init() {}
    init(sessionID: String) { self.sessionID = sessionID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: sessionID) { try await AlarmCancellation.cancel(id: id) }
        guard let activity = Activity<DragonAttributes>.activities.first(where: { $0.attributes.sessionID.uuidString == sessionID }) else {
            return .result()
        }
        await activity.end(activity.content, dismissalPolicy: .immediate)
        return .result()
    }
}
