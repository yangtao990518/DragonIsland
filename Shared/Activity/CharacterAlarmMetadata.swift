#if canImport(AlarmKit)
import AlarmKit

@available(iOS 26.0, *)
struct CharacterAlarmMetadata: AlarmMetadata {
    let characterID: String
    let voiceID: String
    let alarmID: String
    let title: String
}
#endif
