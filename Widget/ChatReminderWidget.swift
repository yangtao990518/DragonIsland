import ActivityKit
import SwiftUI
import WidgetKit

struct ChatReminderWidget: Widget {
    private func character(_ attributes: ChatReminderAttributes) -> CompanionCharacter {
        CharacterCatalog.resolve(attributes.characterID, in: CharacterCatalog.load())
    }
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatReminderAttributes.self) { context in
            HStack(spacing: 12) {
                CharacterAvatar(character: character(context.attributes), size: 42)
                    .overlay(alignment: .topTrailing) { UnreadBadge(count: context.state.unreadCount).offset(x: 5, y: -5) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(context.attributes.characterName)发来消息").font(.headline)
                    Text(context.state.preview).font(.subheadline).lineLimit(2)
                    Text("\(context.state.unreadCount) 条未读 · 轻点进入聊天").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }.padding(16).activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
                .foregroundStyle(.white).widgetURL(ChatDeepLink.url(context.attributes.conversationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        CharacterAvatar(character: character(context.attributes), size: 28)
                        Text(context.attributes.characterName).font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 5) { UnreadBadge(count: context.state.unreadCount); Text("未读").font(.caption).foregroundStyle(.white.opacity(0.7)) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.state.preview).font(.subheadline).lineLimit(3)
                        Link(destination: ChatDeepLink.url(context.attributes.conversationID)) {
                            Text("打开聊天").font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color(red: 0.12, green: 0.66, blue: 0.39), in: Capsule())
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                UnreadTimerAvatar(character: character(context.attributes),
                    epoch: context.attributes.animationStartedAt ?? context.state.sentAt, size: 24)
            } compactTrailing: {
                UnreadBadge(count: context.state.unreadCount)
            } minimal: {
                CharacterAvatar(character: character(context.attributes), size: 20)
                    .overlay(alignment: .topTrailing) { Circle().fill(.red).frame(width: 6, height: 6) }
                    .accessibilityLabel("\(context.attributes.characterName)，\(context.state.unreadCount)条未读")
            }
            .keylineTint(Color(red: 0.95, green: 0.22, blue: 0.28))
            .widgetURL(ChatDeepLink.url(context.attributes.conversationID))
        }
    }
}
