#if canImport(AlarmKit)
import AppIntents
import Foundation

@available(iOS 26.0, *)
struct StopCharacterAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止角色闹钟"
    static var openAppWhenRun = false
    @Parameter(title: "闹钟标识") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try await AlarmCancellation.cancel(id: id) }
        return .result()
    }
}
#endif
