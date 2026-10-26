#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// Shared metadata gives AlarmKit and the extension the same concrete attributes
/// type. Only the firing presentation is needed: fixed alarms have no countdown.
@available(iOS 26.0, *)
struct CharacterAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<CharacterAlarmMetadata>.self) { context in
            let metadata = context.attributes.metadata
            let character = CharacterCatalog.resolve(metadata?.characterID, in: CharacterCatalog.load())
            HStack(spacing: 14) {
                CharacterStanding(character: character, width: 60, height: 88)
                VStack(alignment: .leading, spacing: 10) {
                    Text(metadata?.title ?? "时间到啦").font(.headline).lineLimit(2)
                    Text("\(character.name)来提醒你啦").font(.subheadline).foregroundStyle(DragonPalette.lavender)
                    stop(metadata)
                }
                Spacer(minLength: 0)
            }
            .padding(16).foregroundStyle(DragonPalette.softWhite)
            .activityBackgroundTint(DragonPalette.ink)
            .activitySystemActionForegroundColor(DragonPalette.lavender)
        } dynamicIsland: { context in
            let metadata = context.attributes.metadata
            let character = CharacterCatalog.resolve(metadata?.characterID, in: CharacterCatalog.load())
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DragonPortrait(character: character, size: 28)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "alarm.fill").foregroundStyle(DragonPalette.lavender)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        CharacterStanding(character: character, width: 58, height: 80)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metadata?.title ?? "时间到啦").font(.headline).lineLimit(2)
                            stop(metadata)
                        }
                        Spacer(minLength: 0)
                    }.foregroundStyle(DragonPalette.softWhite).padding(.bottom, 6)
                }
            } compactLeading: {
                DragonPortrait(character: character, size: 28)
            } compactTrailing: {
                Image(systemName: "alarm.fill").foregroundStyle(DragonPalette.lavender)
            } minimal: {
                DragonPortrait(character: character, size: 24)
            }
        }
    }

    @ViewBuilder private func stop(_ metadata: CharacterAlarmMetadata?) -> some View {
        if let metadata {
            Button(intent: StopCharacterAlarmIntent(alarmID: metadata.alarmID)) {
                Label("停止响铃", systemImage: "stop.fill")
            }.tint(DragonPalette.lavender)
        }
    }
}
#endif
