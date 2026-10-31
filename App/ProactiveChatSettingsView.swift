import SwiftUI

struct ProactiveChatSettingsView: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var coordinator: ProactiveChatCoordinator
    let character: CompanionCharacter
    @Environment(\.dismiss) private var dismiss
    @State private var preference: ProactiveCharacterSettings
    @State private var failure: String?

    init(store: ChatStore, coordinator: ProactiveChatCoordinator, character: CompanionCharacter) {
        self.store = store; self.coordinator = coordinator; self.character = character
        var value = store.proactiveState.settings.preference(for: character.id)
        value.intervalMinutes = value.intervalMinutes ?? 60
        _preference = State(initialValue: value)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    CharacterAvatar(character: character, size: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("让\(character.name)主动找你").font(.system(size: 21, weight: .semibold, design: .serif))
                        Text("她的时间、间隔和联系位置，单独记住。").font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 8)
                MoonCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("允许她主动聊天", isOn: $preference.enabled).font(.headline)
                            .accessibilityIdentifier("proactiveChatEnabled")
                        Text("使用她现有的模型与人设，提前准备真实消息，会使用你的 AI 接口额度。")
                            .font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6)).lineSpacing(4)
                    }
                }
                MoonCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("允许联系的时间", systemImage: "clock").font(.system(size: 18, weight: .semibold, design: .serif))
                        DatePicker("开始", selection: minute(\.startMinute), displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: minute(\.endMinute), displayedComponents: .hourAndMinute)
                        Divider().overlay(MoonPalette.gold.opacity(0.15))
                        Stepper(value: Binding(get: { preference.intervalMinutes ?? 60 }, set: { preference.intervalMinutes = $0 }), in: 15...480, step: 15) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("最短间隔 \(preference.intervalMinutes ?? 60) 分钟").font(.subheadline.weight(.medium))
                                Text("实际联系时间仍然随机").font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.55))
                            }
                        }.accessibilityIdentifier("proactiveMinimumInterval")
                        Text("例如 10:00–18:00、最短间隔 60 分钟：只在这段时间随机联系，两条主动消息至少相隔 60 分钟，不是每小时整点发送。其他时间不安排新提醒，也不集中补发。")
                            .font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6)).lineSpacing(4)
                    }
                }
                MoonCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("在哪里找你", systemImage: "bubble.left.and.bubble.right").font(.system(size: 18, weight: .semibold, design: .serif))
                        Picker("联系位置", selection: $preference.destination) {
                            Text("私聊我").tag(ProactiveCharacterSettings.Destination.direct)
                            Text("群聊里 @我").tag(ProactiveCharacterSettings.Destination.group)
                        }.pickerStyle(.segmented)
                        if preference.destination == .group {
                            let groups = store.conversations.filter { $0.kind == .group && $0.characterIDs.contains(character.id) }
                            Picker("选择群聊", selection: $preference.groupID) {
                                Text("请选择群聊").tag(Optional<UUID>.none)
                                ForEach(groups) { group in Text(group.name).tag(Optional(group.id)) }
                            }
                            if groups.isEmpty {
                                Text("先创建一个包含\(character.name)的群聊。").font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6))
                            }
                        }
                        Toggle("系统消息通知", isOn: optionalFlag(\.notifications, fallback: true))
                        Toggle("灵动岛未读提醒", isOn: optionalFlag(\.islandReminder, fallback: true))
                        if !coordinator.notificationsAllowed {
                            Text("保存时可申请系统通知权限，也可在 iPhone 设置中开启。").font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6))
                        }
                    }
                }
                plans
                Text("修改设置只重新安排\(character.name)的待发消息。手机本地版在 App 可运行时提前准备，锁屏后由系统投递已准备的通知；队列用完后需 App 再次运行。后台到点刷新灵动岛仍不能保证。")
                    .font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6)).lineSpacing(4).padding(.horizontal, 4)
                Button("保存\(character.name)的设置") { save() }.buttonStyle(MoonPrimaryButton())
                    .accessibilityIdentifier("saveProactiveChat")
            }.padding(18).padding(.bottom, 20)
        }
        .background { MoonBackdrop().ignoresSafeArea() }
        .foregroundStyle(MoonPalette.ink).tint(MoonPalette.violet)
        .navigationTitle("主动聊天").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(MoonPalette.paper, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .task { await coordinator.refresh(prepare: false) }
        .alert("主动聊天", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("知道了", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private var plans: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(character.name)的待发安排").font(.system(size: 18, weight: .semibold, design: .serif))
                if coordinator.preparing { ProgressView("正在准备消息…") }
                let ready = store.proactiveState.slots.filter { $0.characterID == character.id && $0.status == .ready && $0.scheduledAt > .now }
                    .sorted { $0.scheduledAt < $1.scheduledAt }
                if ready.isEmpty { Text("暂无待发消息").font(.subheadline).foregroundStyle(MoonPalette.ink.opacity(0.55)) }
                ForEach(ready) { slot in
                    HStack { Text(slot.scheduledAt, style: .date); Spacer(); Text(slot.scheduledAt, style: .time) }.font(.caption)
                }
                if let status = coordinator.status { Text(status).font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6)) }
                Button("重试准备她的失败消息") { coordinator.beginPreparation(retry: true, characterID: character.id) }
                    .disabled(coordinator.preparing || !store.proactiveState.settings.preference(for: character.id).enabled)
                Text("以上为已经保存的安排，编辑中的内容点保存后生效。本地待发队列最多提前保留 32 条，由两位角色共用；App 继续运行时会补充后续安排。")
                    .font(.caption2).foregroundStyle(MoonPalette.ink.opacity(0.55)).lineSpacing(4)
            }
        }
    }
    private func save() {
        guard store.saveProactivePreference(preference, for: character.id) else { failure = store.error; store.error = nil; return }
        Task {
            if preference.enabled, preference.notifications == true { await coordinator.authorizeNotifications() }
            await coordinator.settingsChanged()
        }
        dismiss()
    }
    private func optionalFlag(_ key: WritableKeyPath<ProactiveCharacterSettings, Bool?>, fallback: Bool) -> Binding<Bool> {
        Binding(get: { preference[keyPath: key] ?? fallback }, set: { preference[keyPath: key] = $0 })
    }
    private func minute(_ key: WritableKeyPath<ProactiveChatWindow, Int>) -> Binding<Date> {
        Binding(get: {
            let value = (preference.window ?? ProactiveChatWindow())[keyPath: key]
            return Calendar.current.date(bySettingHour: value / 60, minute: value % 60, second: 0, of: .now) ?? .now
        }, set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            var window = preference.window ?? ProactiveChatWindow()
            window[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            preference.window = window
        })
    }
}
