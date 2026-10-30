import ActivityKit
import Combine
import UIKit
import UserNotifications

/// Local preparation and delivery only. No background timer or APNs capability is implied.
@MainActor
final class ProactiveChatCoordinator: ObservableObject {
    @Published private(set) var preparing = false
    @Published private(set) var status: String?
    @Published private(set) var notificationsAllowed = false
    private let store: ChatStore
    private var preparation: Task<Void, Never>?
    private var refreshing = false
    private let prefix = "maiverse.chat.proactive."

    init(store: ChatStore) { self.store = store }

    func authorizeNotifications() async {
        do {
            notificationsAllowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if !notificationsAllowed { status = "通知尚未授权，可在 iPhone 设置中开启。" }
        } catch { status = "未能取得通知权限，请在系统设置中检查。" }
    }

    func settingsChanged() async {
        preparation?.cancel()
        // Reconcile immediately even when an old model request is still finishing.
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix(prefix) }.map { $0.request.identifier })
        await refresh(prepare: false)
    }

    func refresh(prepare shouldPrepare: Bool = true) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let deliveredIDs = store.deliverProactiveChats()
        if let id = store.visibleConversationID { store.markRead(id) }
        await reconcileNotifications()
        await updateIsland(alert: !deliveredIDs.isEmpty)
        consumePendingNavigation()
        if shouldPrepare, UIApplication.shared.applicationState == .active, preparation == nil {
            beginPreparation(retry: false)
        }
    }

    func beginPreparation(retry: Bool) {
        guard preparation == nil, store.proactiveState.settings.enabled else { return }
        if retry { store.retryProactivePreparations() }
        let created = store.planProactiveChats()
        let pendingIDs = Set(created + store.proactiveState.slots.filter { $0.status == .planned }.map(\.id))
        let ids = store.proactiveState.slots.filter { pendingIDs.contains($0.id) }.sorted { $0.scheduledAt < $1.scheduledAt }.map(\.id)
        guard !ids.isEmpty else { return }
        preparing = true
        status = "正在准备下一允许时段的消息…"
        preparation = Task { [weak self] in
            guard let self else { return }
            var failures = 0
            for id in ids {
                if Task.isCancelled { break }
                do { try await store.prepareProactiveChat(id) }
                catch is CancellationError { break }
                catch { failures += 1; status = error.localizedDescription }
            }
            preparing = false; preparation = nil
            if failures == 0, !Task.isCancelled { status = "已准备好消息，将在允许时段随机提醒。" }
            await refresh(prepare: false)
        }
    }

    private func reconcileNotifications() async {
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        notificationsAllowed = [.authorized, .provisional, .ephemeral].contains(authorization.authorizationStatus)
        let settings = store.proactiveState.settings
        let slots = store.proactiveState.slots
        let future = slots.filter { slot in
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: slot.timeZoneID) ?? .current
            return slot.status == .ready && slot.policyID == store.proactiveState.policyID && slot.scheduledAt > .now
                && settings.enabled && settings.characters[slot.characterID]?.enabled == true
                && settings.window.allows(slot.scheduledAt, calendar: calendar)
                && store.conversation(slot.conversationID)?.characterIDs.contains(slot.characterID) == true
        }
        let validIDs = Set(future.map(\.notificationID))
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.identifier.hasPrefix(prefix) && (!validIDs.contains($0.identifier) || !settings.notifications || !notificationsAllowed)
        }.map(\.identifier))
        let existing = Set(pending.map(\.identifier))
        // Leave room for companion alarms; iOS has a finite local notification queue.
        let capacity = max(0, 60 - pending.filter { !$0.identifier.hasPrefix(prefix) }.count)
        if settings.notifications, notificationsAllowed {
            for slot in future.sorted(by: { $0.scheduledAt < $1.scheduledAt }).prefix(capacity) {
                if existing.contains(slot.notificationID) { continue }
                let content = UNMutableNotificationContent()
                content.title = slot.characterName + (store.conversation(slot.conversationID)?.kind == .group ? " 在群里 @了你" : " 发来消息")
                content.body = String((slot.text ?? "").prefix(180))
                content.sound = .default
                content.threadIdentifier = slot.conversationID.uuidString
                content.userInfo = ["chatConversationID": slot.conversationID.uuidString]
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: slot.timeZoneID) ?? .current
                var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slot.scheduledAt)
                // Wall-clock components follow the phone's timezone; do not bypass the quiet window.
                parts.timeZone = nil
                do {
                    try await center.add(UNNotificationRequest(identifier: slot.notificationID, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                    let current = store.proactiveState
                    if current.settings.enabled, current.settings.notifications, current.policyID == slot.policyID,
                       current.slots.contains(where: { $0.id == slot.id && $0.status == .ready }) {
                        store.setProactiveNotificationScheduled(slot.id, scheduled: true)
                    } else { center.removePendingNotificationRequests(withIdentifiers: [slot.notificationID]) }
                } catch { status = "有消息未能安排系统提醒，请打开主动聊天设置检查。" }
            }
        }
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.compactMap { notification in
            guard notification.request.identifier.hasPrefix(prefix),
                  let raw = notification.request.content.userInfo["chatConversationID"] as? String,
                  let id = UUID(uuidString: raw) else { return nil }
            return !settings.enabled || (store.conversation(id)?.unreadProactiveCount ?? 0) == 0 ? notification.request.identifier : nil
        })
    }

    private func updateIsland(alert: Bool) async {
        let unread = store.conversations.filter { $0.unreadProactiveCount > 0 }
        let total = unread.reduce(0) { $0 + $1.unreadProactiveCount }
        let latest = unread.flatMap { chat in chat.messages.filter { $0.isProactive == true && $0.createdAt > (chat.lastReadAt ?? .distantPast) }.map { (chat, $0) } }
            .max { $0.1.createdAt < $1.1.createdAt }
        let settings = store.proactiveState.settings
        let activities = Activity<ChatReminderAttributes>.activities
        guard settings.enabled, settings.islandReminder, let (chat, message) = latest,
              let character = store.character(message.characterID), ActivityAuthorizationInfo().areActivitiesEnabled else {
            for activity in activities { await activity.end(activity.content, dismissalPolicy: .immediate) }
            return
        }
        let state = ChatReminderAttributes.ContentState(preview: String(message.text.prefix(100)), unreadCount: total, sentAt: message.createdAt)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600), relevanceScore: 100)
        let current = activities.first { $0.attributes.conversationID == chat.id && [.active, .stale].contains($0.activityState) }
        for activity in activities where activity.id != current?.id { await activity.end(activity.content, dismissalPolicy: .immediate) }
        if let current {
            guard current.content.state != state else { return }
            let mayAlert = alert && settings.window.allows(.now) && store.visibleConversationID != chat.id
            await current.update(content, alertConfiguration: mayAlert
                ? AlertConfiguration(title: "\(character.name)发来消息", body: "\(String(message.text.prefix(80)))", sound: .default) : nil)
        } else if UIApplication.shared.applicationState == .active {
            do { _ = try Activity.request(attributes: ChatReminderAttributes(conversationID: chat.id, characterID: character.id,
                characterName: character.name), content: content, pushType: nil) }
            catch { status = "消息已保存，灵动岛提醒未能启动，请检查实时活动权限。" }
        }
    }

    func consumePendingNavigation() {
        guard let raw = UserDefaults.standard.string(forKey: ChatDeepLink.pendingKey), let id = UUID(uuidString: raw) else { return }
        UserDefaults.standard.removeObject(forKey: ChatDeepLink.pendingKey)
        if store.conversation(id) != nil { store.requestedConversationID = id }
    }
}
