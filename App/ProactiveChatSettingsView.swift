import SwiftUI

struct ProactiveChatSettingsView: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var coordinator: ProactiveChatCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ProactiveChatSettings
    @State private var failure: String?

    init(store: ChatStore, coordinator: ProactiveChatCoordinator) {
        self.store = store; self.coordinator = coordinator
        _settings = State(initialValue: store.proactiveState.settings)
    }

    var body: some View {
        Form {
            Section {
                Toggle("允许 AI 主动找我聊天", isOn: $settings.enabled)
                    .accessibilityIdentifier("proactiveChatEnabled")
            } footer: {
                Text("使用各角色现有模型与人设。App 运行时提前准备真实消息，再在允许时段随机投递；会使用你的 DeepSeek 额度。")
            }
            Section {
                DatePicker("允许开始", selection: minute(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("允许结束", selection: minute(\.endMinute), displayedComponents: .hourAndMinute)
                Stepper("每个角色每时段 \(settings.dailyCount) 次", value: $settings.dailyCount, in: 1...3)
                    .accessibilityIdentifier("proactiveDailyCount")
                Text(settings.window.startMinute == settings.window.endMinute ? "开始与结束时间不能相同。" : "只在选定时段联系你；其他时间不安排新提醒。跨午夜的时段也可以设置。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("聊天推送时间 · 手机本地时间") } footer: {
                Text("默认 10:00–18:00 允许聊天，18:00 到次日 10:00 不联系。更改时段后会取消旧的待发消息，按新时段重新准备。")
            }
            ForEach(store.characters) { character in
                Section(character.name) {
                    Toggle("允许\(character.name)主动联系", isOn: characterBinding(character.id, \.enabled))
                        .accessibilityIdentifier("proactiveCharacter_\(character.id)")
                    Picker("联系位置", selection: characterBinding(character.id, \.destination)) {
                        Text("私聊我").tag(ProactiveCharacterSettings.Destination.direct)
                        Text("群聊里 @我").tag(ProactiveCharacterSettings.Destination.group)
                    }
                    if (settings.characters[character.id] ?? ProactiveCharacterSettings()).destination == .group {
                        let groups = store.conversations.filter { $0.kind == .group && $0.characterIDs.contains(character.id) }
                        Picker("选择群聊", selection: characterBinding(character.id, \.groupID)) {
                            Text("请选择群聊").tag(Optional<UUID>.none)
                            ForEach(groups) { group in Text(group.name).tag(Optional(group.id)) }
                        }
                        if groups.isEmpty { Text("先在聊天页创建一个包含\(character.name)的群组。").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                Toggle("系统消息通知", isOn: $settings.notifications)
                Toggle("灵动岛未读提醒", isOn: $settings.islandReminder)
                if !coordinator.notificationsAllowed { Text("系统通知未授权；保存时可申请，也可在 iPhone 设置中开启。").font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("本地版已准备的通知可在锁屏后送达。App 被挂起时无法持续生成新消息，灵动岛在 App 获得运行机会时更新；不会占用或改写原陪伴计时。")
            }
            Section("当前已保存的安排") {
                if coordinator.preparing { ProgressView("正在准备消息…") }
                let ready = store.proactiveState.slots.filter { $0.status == .ready && $0.scheduledAt > .now }.sorted { $0.scheduledAt < $1.scheduledAt }
                if ready.isEmpty { Text("暂无待发消息").foregroundStyle(.secondary) }
                ForEach(ready) { slot in
                    HStack {
                        Text(slot.characterName)
                        Spacer()
                        Text(slot.scheduledAt, style: .date)
                        Text(slot.scheduledAt, style: .time)
                    }.font(.caption)
                }
                if let status = coordinator.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                Button("重试准备已保存时段的消息") { coordinator.beginPreparation(retry: true) }
                    .disabled(coordinator.preparing || !store.proactiveState.settings.enabled)
                Text("以上是已经保存的安排；编辑中的设置点保存后才生效。不会为了补齐次数在禁止时段发消息。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("主动聊天").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard store.saveProactiveSettings(settings) else { failure = store.error; store.error = nil; return }
                    Task {
                        if settings.enabled, settings.notifications { await coordinator.authorizeNotifications() }
                        await coordinator.settingsChanged()
                        coordinator.beginPreparation(retry: false)
                    }
                    dismiss()
                }.accessibilityIdentifier("saveProactiveChat")
            }
        }
        .task { await coordinator.refresh(prepare: false) }
        .alert("主动聊天", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("知道了", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func characterBinding<Value>(_ id: String, _ key: WritableKeyPath<ProactiveCharacterSettings, Value>) -> Binding<Value> {
        Binding(get: { (settings.characters[id] ?? ProactiveCharacterSettings())[keyPath: key] }, set: { value in
            var character = settings.characters[id] ?? ProactiveCharacterSettings()
            character[keyPath: key] = value; settings.characters[id] = character
        })
    }
    private func minute(_ key: WritableKeyPath<ProactiveChatWindow, Int>) -> Binding<Date> {
        Binding(get: {
            let value = settings.window[keyPath: key]
            return Calendar.current.date(bySettingHour: value / 60, minute: value % 60, second: 0, of: .now) ?? .now
        }, set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            settings.window[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
}
