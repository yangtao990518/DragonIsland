import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DragonIslandWidgetBundle: WidgetBundle {
    var body: some Widget { DragonLiveActivity() }
}

struct DragonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DragonAttributes.self) { context in
            DragonActivityPanel(context: context, compact: false)
                .padding(16)
                .activityBackgroundTint(DragonPalette.ink)
                .activitySystemActionForegroundColor(DragonPalette.lavender)
                .widgetURL(URL(string: "dragonisle://companion"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("小白", systemImage: context.state.mood.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DragonPalette.lavender)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DragonCountdown(state: context.state, expired: context.isStale)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(width: 64, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DragonActivityPanel(context: context, compact: true)
                        .padding(.top, 4)
                }
            } compactLeading: {
                DragonPortrait()
            } compactTrailing: {
                DragonCountdown(state: context.state, expired: context.isStale)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DragonPalette.lavender)
                    .frame(width: 46)
            } minimal: {
                DragonPortrait()
            }
            .keylineTint(DragonPalette.lavender)
            .widgetURL(URL(string: "dragonisle://companion"))
        }
    }
}

private struct DragonActivityPanel: View {
    let context: ActivityViewContext<DragonAttributes>
    let compact: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image("DragonFull")
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 72 : 84, height: compact ? 72 : 84)
                    .rotationEffect(.degrees(context.state.revision.isMultiple(of: 2) ? 0 : -3))
                    .animation(.easeInOut(duration: 0.35), value: context.state.revision)
                    .accessibilityLabel("白紫龙娘小白")
                VStack(alignment: .leading, spacing: 6) {
                    if !compact {
                        HStack {
                            Text("小白 · \(context.state.mood.title)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DragonPalette.lavender)
                            Spacer(minLength: 4)
                            DragonCountdown(state: context.state, expired: context.isStale)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .frame(width: 62, alignment: .trailing)
                        }
                    }
                    Text(context.isStale ? "这轮结束啦，辛苦了。" : context.state.message)
                        .font(.system(size: compact ? 13 : 14, weight: .medium))
                        .foregroundStyle(DragonPalette.softWhite)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.opacity)
                    Text(context.isStale ? "打开 App，再开始一轮。" : "陪你把这一小段时间过好。")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 7) {
                if !context.isStale {
                    Button(intent: GreetDragonIntent(sessionID: context.attributes.sessionID.uuidString)) {
                        Label("招呼", systemImage: "hand.wave.fill")
                    }
                    Button(intent: ChangeDragonMoodIntent(sessionID: context.attributes.sessionID.uuidString)) {
                        Label("心情", systemImage: "sparkles")
                    }
                }
                Button(intent: EndDragonSessionIntent(sessionID: context.attributes.sessionID.uuidString)) {
                    Label("结束", systemImage: "xmark")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.bordered)
            .tint(DragonPalette.lavender)
        }
        .foregroundStyle(DragonPalette.softWhite)
    }
}
