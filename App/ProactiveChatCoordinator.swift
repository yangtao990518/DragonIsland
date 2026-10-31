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
        if !store.proactiveState.settings.enabled { preparation?.cancel() }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let current = store.proactiveState
        center.removePendingNotificationRequests(withIdentifiers: pending.compactMap { request in
            guard request.identifier.hasPrefix(prefix) else { return nil }
            guard let slot = current.slots.first(where: { $0.notificationID == request.identifier }) else { return request.identifier }
            let preference = current.settings.preference(for: slot.characterID)
            return slot.status != .ready || slot.policyID != current.policy(for: slot.characterID)
                || !preference.enabled || preference.notifications != true ? request.identifier : nil
        })
        // Reconcile only invalid role policies; preserve other roles' scheduled
        // notifications and any in-flight preparation that still belongs to them.
        await refresh()
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

    func beginPreparation(retry: Bool, characterID: String? = nil) {
        guard preparation == nil, store.proactiveState.settings.enabled else { return }
        if retry { store.retryProactivePreparations(characterID: characterID) }
        let created = store.planProactiveChats()
        let pendingIDs = Set(created + store.proactiveState.slots.filter { $0.status == .planned }.map(\.id))
        let ids = store.proactiveState.slots.filter { pendingIDs.contains($0.id) && (characterID == nil || $0.characterID == characterID) }.sorted { $0.scheduledAt < $1.scheduledAt }.map(\.id)
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
            await refresh(prepare: false)
            if failures == 0, !Task.isCancelled, status == "正在准备下一允许时段的消息…" {
                status = "消息已准备好，可在下方查看已保存的安排。"
            }
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
            return slot.status == .ready && slot.policyID == store.proactiveState.policy(for: slot.characterID) && slot.scheduledAt > .now
                && settings.enabled && settings.characters[slot.characterID]?.enabled == true
                && settings.preference(for: slot.characterID).window!.allows(slot.scheduledAt, calendar: calendar)
                && settings.preference(for: slot.characterID).notifications == true
                && store.conversation(slot.conversationID)?.characterIDs.contains(slot.characterID) == true
        }
        let validIDs = Set(future.map(\.notificationID))
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.identifier.hasPrefix(prefix) && (!validIDs.contains($0.identifier) || !notificationsAllowed)
        }.map(\.identifier))
        let existing = Set(pending.map(\.identifier))
        // Leave room for companion alarms; iOS has a finite local notification queue.
        let capacity = max(0, 60 - pending.filter { !$0.identifier.hasPrefix(prefix) }.count)
        if notificationsAllowed, future.count > capacity {
            status = "系统提醒队列已满，部分消息暂时只保存在 App 中。"
        }
        if notificationsAllowed {
            for slot in future.sorted(by: { $0.scheduledAt < $1.scheduledAt }).prefix(capacity) {
                if existing.contains(slot.notificationID) { continue }
                let content = UNMutableNotificationContent()
                content.title = slot.characterName + (store.conversation(slot.conversationID)?.kind == .group ? " 在群里 @了你" : " 发来消息")
                content.body = String((slot.text ?? "").prefix(180))
                content.sound = .default
                content.threadIdentifier = slot.conversationID.uuidString
                content.userInfo = ["chatConversationID": slot.conversationID.uuidString, "chatCharacterID": slot.characterID]
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: slot.timeZoneID) ?? .current
                var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slot.scheduledAt)
                // Wall-clock components follow the phone's timezone; do not bypass the quiet window.
                parts.timeZone = nil
                do {
                    try await center.add(UNNotificationRequest(identifier: slot.notificationID, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                    let current = store.proactiveState
                    if current.settings.preference(for: slot.characterID).enabled,
                       current.settings.preference(for: slot.characterID).notifications == true,
                       current.policy(for: slot.characterID) == slot.policyID,
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
        let settings = store.proactiveState.settings
        let unread = store.conversations.flatMap { chat in
            chat.messages.filter { message in
                let preference = settings.preference(for: message.characterID ?? "")
                return message.isProactive == true && message.createdAt > (chat.lastReadAt ?? .distantPast)
                    && preference.enabled && preference.islandReminder == true
            }.map { (chat, $0) }
        }
        let total = unread.count
        let latest = unread.max { $0.1.createdAt < $1.1.createdAt }
        let activities = Activity<ChatReminderAttributes>.activities
        guard settings.enabled, let (chat, message) = latest,
              let character = store.character(message.characterID), ActivityAuthorizationInfo().areActivitiesEnabled else {
            for activity in activities { await activity.end(activity.content, dismissalPolicy: .immediate) }
            return
        }
        let state = ChatReminderAttributes.ContentState(preview: String(message.text.prefix(100)), unreadCount: total, sentAt: message.createdAt)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600), relevanceScore: 100)
        let current = activities.first { $0.attributes.conversationID == chat.id && $0.attributes.characterID == character.id
            && $0.attributes.animationStartedAt != nil && [.active, .stale].contains($0.activityState) }
        for activity in activities where activity.id != current?.id { await activity.end(activity.content, dismissalPolicy: .immediate) }
        if let current {
            guard current.content.state != state else { return }
            let mayAlert = alert && settings.preference(for: character.id).window!.allows(.now) && store.visibleConversationID != chat.id
            await current.update(content, alertConfiguration: mayAlert
                ? AlertConfiguration(title: "\(character.name)发来消息", body: "\(String(message.text.prefix(80)))", sound: .default) : nil)
        } else if UIApplication.shared.applicationState == .active {
            do { _ = try Activity.request(attributes: ChatReminderAttributes(conversationID: chat.id, characterID: character.id,
                characterName: character.name, animationStartedAt: .now), content: content, pushType: nil) }
            catch { status = "消息已保存，灵动岛提醒未能启动，请检查实时活动权限。" }
        }
    }

    func consumePendingNavigation() {
        guard let raw = UserDefaults.standard.string(forKey: ChatDeepLink.pendingKey), let id = UUID(uuidString: raw) else { return }
        UserDefaults.standard.removeObject(forKey: ChatDeepLink.pendingKey)
        if store.conversation(id) != nil { store.requestedConversationID = id }
    }
}
