import ActivityKit
import SwiftUI
import WidgetKit

struct ChatReminderWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatReminderAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(context.attributes.characterName)发来消息").font(.headline)
                    Text(context.state.preview).font(.subheadline).lineLimit(2)
                    Text("\(context.state.unreadCount) 条未读 · 轻点进入聊天").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(16)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .foregroundStyle(.white)
                .widgetURL(ChatDeepLink.url(context.attributes.conversationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.characterName, systemImage: "bubble.left.fill").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.unreadCount) 条未读").font(.caption).foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.state.preview).font(.subheadline).lineLimit(3)
                        Link("打开聊天", destination: ChatDeepLink.url(context.attributes.conversationID))
                            .font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "bubble.left.fill").foregroundStyle(.cyan)
            } compactTrailing: {
                Text(context.state.unreadCount > 99 ? "99+" : "\(context.state.unreadCount)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.cyan)
            } minimal: {
                Image(systemName: "bubble.left.fill").foregroundStyle(.cyan)
            }
            .keylineTint(.cyan)
            .widgetURL(ChatDeepLink.url(context.attributes.conversationID))
        }
    }
}
