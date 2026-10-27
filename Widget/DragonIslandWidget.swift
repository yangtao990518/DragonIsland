import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DragonIslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        DragonLiveActivity()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { CharacterAlarmWidget() }
        #endif
    }
}

struct DragonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DragonAttributes.self) { context in
            LockScreenCompanion(context: context)
                .padding(14)
                .activityBackgroundTint(DragonPalette.ink)
                .activitySystemActionForegroundColor(DragonPalette.lavender)
                .widgetURL(URL(string: "dragonisle://companion"))
        } dynamicIsland: { context in
            let character = CharacterCatalog.resolve(context.attributes.characterID, in: CharacterCatalog.load())
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 3) {
                        CharacterAvatar(character: character, size: 22)
                        Text(context.attributes.companionName)
                    }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DragonPalette.lavender)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DragonCountdown(state: context.state, expired: context.isStale)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 58, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Put controls beside art to keep the expanded content under 160pt.
                    HStack(spacing: 10) {
                        CharacterStanding(character: character, width: 68, height: 88)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(context.isStale ? "这轮结束啦，辛苦了。" : context.state.message)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .contentTransition(.opacity)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(context.isStale ? "打开 mAIverse，再陪你一会儿。" : context.state.mood.title)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                            ActivityControls(context: context)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .foregroundStyle(DragonPalette.softWhite)
                    .padding(5)
                    .background { IslandSceneBackdrop(scene: context.state.islandScene, wide: true) }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } compactLeading: {
                IslandMotionPortrait(character: character, state: context.state)
            } compactTrailing: {
                DragonCountdown(state: context.state, expired: context.isStale)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DragonPalette.softWhite)
                    .frame(width: 46, height: 32)
                    .background { IslandSceneBackdrop(scene: context.state.islandScene) }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .id(context.state.islandScene.rawValue)
                    .transition(.identity)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
            } minimal: {
                // Keep the tiny secondary-activity badge static. Only the
                // normal compact island needs the full 30fps frame stack.
                DragonPortrait(character: character, size: 26)
                    .background { IslandSceneBackdrop(scene: context.state.islandScene) }
                    .clipShape(Circle())
            }
            .keylineTint(DragonPalette.lavender)
            .widgetURL(URL(string: "dragonisle://companion"))
        }
    }
}

private struct LockScreenCompanion: View {
    let context: ActivityViewContext<DragonAttributes>

    var body: some View {
        let character = CharacterCatalog.resolve(context.attributes.characterID, in: CharacterCatalog.load())
        HStack(spacing: 14) {
            CharacterStanding(character: character, width: 76, height: 108)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(context.attributes.companionName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DragonPalette.lavender)
                    Spacer(minLength: 4)
                    DragonCountdown(state: context.state, expired: context.isStale)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(width: 66, alignment: .trailing)
                }
                Text(context.isStale ? "这轮陪伴结束啦，辛苦了。" : context.state.message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                ActivityControls(context: context)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(DragonPalette.softWhite)
        .background { IslandSceneBackdrop(scene: context.state.islandScene, wide: true) }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ActivityControls: View {
    let context: ActivityViewContext<DragonAttributes>

    var body: some View {
        HStack(spacing: 5) {
            if !context.isStale {
                Button(intent: GreetDragonIntent(sessionID: context.attributes.sessionID.uuidString)) {
                    ActivityControlLabel(title: "招呼", symbol: "hand.wave.fill")
                }
                Button(intent: ChangeDragonMoodIntent(sessionID: context.attributes.sessionID.uuidString)) {
                    ActivityControlLabel(title: "心情", symbol: "sparkles")
                }
            }
            Button(intent: EndDragonSessionIntent(sessionID: context.attributes.sessionID.uuidString)) {
                ActivityControlLabel(title: "结束", symbol: "xmark")
            }
        }
        .buttonStyle(.plain)
        .tint(DragonPalette.lavender)
    }
}

private struct ActivityControlLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(title).font(.system(size: 10, weight: .medium))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .foregroundStyle(DragonPalette.lavender)
        .background(DragonPalette.lavender.opacity(0.18), in: Capsule())
        .contentShape(Capsule())
    }
}

