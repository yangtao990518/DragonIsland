import SwiftUI
import UIKit

struct CharacterVoicePicker: View {
    @ObservedObject var alarms: CharacterAlarmStore
    let character: CompanionCharacter
    @Binding var voiceID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section(header: Text("\(character.name)的到点语音"),
                    footer: Text("点播放键试听，点文字选择。每个角色单独保存。")) {
                ForEach(VoiceCatalog.voices(for: character.id, in: alarms.voices)) { voice in
                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            voiceID = voice.id
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: voiceID == voice.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(AppPalette.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(voice.title).font(.headline)
                                    Text(voice.text).font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(voice.duration, specifier: "%.1f") 秒").font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("selectVoice-\(voice.id)")
                        Button { alarms.play(voice) } label: {
                            Image(systemName: alarms.playingID == voice.id ? "stop.fill" : "play.fill")
                                .frame(width: 42, height: 44)
                        }.buttonStyle(.borderless)
                            .accessibilityLabel(alarms.playingID == voice.id ? "停止试听" : "试听\(voice.title)")
                            .accessibilityIdentifier("previewVoice-\(voice.id)")
                    }.padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("选择语音").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .alert("语音试听", isPresented: Binding(get: { alarms.error != nil }, set: { if !$0 { alarms.error = nil } })) {
            Button("知道了", role: .cancel) { alarms.error = nil }
        } message: { Text(alarms.error ?? "") }
        .onDisappear { alarms.stopPreview() }
    }
}

/// Saves the default for this character; changes apply to the next companion session.
struct CompanionVoiceSettings: View {
    @ObservedObject var alarms: CharacterAlarmStore
    let character: CompanionCharacter
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(alarms.voice(for: character.id) == nil ? "到点提醒" : "到点语音提醒", isOn: Binding(
                get: { alarms.preference(for: character.id).enabled },
                set: { alarms.setPreference(characterID: character.id, enabled: $0, voiceID: alarms.voice(for: character.id)?.id) }
            )).accessibilityIdentifier("companionVoiceToggle")
            if let voice = alarms.voice(for: character.id) {
                Button { choosing = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(voice.title).font(.subheadline.weight(.medium))
                            Text(voice.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("chooseCompanionVoice")
            } else {
                Text("到点播放系统提示音。角色语音还在准备中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(alarms.deliveryExplanation).font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $choosing) {
            NavigationStack {
                CharacterVoicePicker(alarms: alarms, character: character, voiceID: Binding(
                    get: { alarms.voice(for: character.id)?.id ?? "" },
                    set: { alarms.setPreference(characterID: character.id,
                        enabled: alarms.preference(for: character.id).enabled, voiceID: $0) }
                ))
            }
        }
    }
}

struct CharacterAlarmEditor: View {
    @ObservedObject var alarms: CharacterAlarmStore
    let character: CompanionCharacter
    var editing: CharacterAlarm?
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var minutes = 25
    @State private var clockTime = Date()
    @State private var title = ""
    @State private var voiceID = ""
    @State private var choosing = false
    @State private var failure: String?

    private var date: Date? {
        if mode == 0 { return CharacterAlarm.countdownDate(minutes: minutes) }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: clockTime)
        return CharacterAlarm.nextDate(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    CharacterAvatar(character: character, size: 38)
                    VStack(alignment: .leading) {
                        Text("让\(character.name)叫你").font(.headline)
                        Text(voiceID == CharacterAlarm.systemSoundID ? "一次提醒 · 到点播放系统提示音" : "一次提醒 · 到点播放所选语音").font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("提醒名称", text: $title).accessibilityIdentifier("alarmTitle")
            }
            Section("提醒时间") {
                Picker("定时方式", selection: $mode) {
                    Text("倒计时").tag(0)
                    Text("指定时间").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("alarmMode")
                if mode == 0 {
                    Stepper("\(minutes) 分钟后", value: $minutes, in: 1...1440)
                        .accessibilityIdentifier("alarmMinutes")
                    HStack {
                        ForEach([1, 5, 25, 60], id: \.self) { value in
                            Button("\(value) 分钟") { minutes = value }
                                .buttonStyle(.bordered).font(.caption)
                                .accessibilityIdentifier("alarmPreset-\(value)")
                        }
                    }
                } else {
                    DatePicker("响铃时间", selection: $clockTime, displayedComponents: .hourAndMinute)
                    Text("选择的时间若已过去，将在明天提醒；仅响一次。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline).foregroundStyle(AppPalette.accent)
                        .accessibilityIdentifier("alarmFireDate")
                }
            }
            Section(voiceID == CharacterAlarm.systemSoundID ? "提醒声音" : "到点语音") {
                if voiceID == CharacterAlarm.systemSoundID {
                    Label("系统提示音", systemImage: "bell.badge")
                        .accessibilityIdentifier("alarmSystemSound")
                    Text("\(character.name)的角色语音还在准备中，不影响设置闹钟和到点提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                Button { choosing = true } label: {
                    HStack {
                        Text(alarms.voices.first { $0.id == voiceID }?.title ?? "选择语音")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }.accessibilityIdentifier("chooseAlarmVoice")
                if let voice = alarms.voices.first(where: { $0.id == voiceID }) {
                    Text(voice.text).font(.subheadline).foregroundStyle(.secondary)
                    Button(alarms.playingID == voice.id ? "停止试听" : "试听这句") { alarms.play(voice) }
                        .accessibilityIdentifier("previewSelectedVoice")
                }
                }
            }
            Section {
                Text(alarms.deliveryExplanation).font(.caption).foregroundStyle(.secondary)
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .navigationTitle(editing == nil ? "新建角色闹钟" : "修改角色闹钟")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(alarms.busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        guard let date else { return }
                        let alarm = CharacterAlarm(id: UUID(), characterID: character.id, voiceID: voiceID,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(character.name)的提醒" : String(title.prefix(60)),
                            date: date)
                        do {
                            _ = try await alarms.schedule(alarm, replacing: editing)
                            alarms.setPreference(characterID: character.id,
                                enabled: alarms.preference(for: character.id).enabled, voiceID: voiceID)
                            dismiss()
                        } catch { failure = error.localizedDescription }
                    }
                } label: {
                    if alarms.busy { ProgressView() } else { Text("保存") }
                }.disabled(voiceID.isEmpty || alarms.busy).accessibilityIdentifier("saveCharacterAlarm")
            }
        }
        .interactiveDismissDisabled(alarms.busy)
        .sheet(isPresented: $choosing) {
            NavigationStack { CharacterVoicePicker(alarms: alarms, character: character, voiceID: $voiceID) }
        }
        .alert("角色提醒", isPresented: Binding(get: { !choosing && (failure != nil || alarms.error != nil) },
            set: { if !$0 { failure = nil; alarms.error = nil } })) {
            Button("知道了", role: .cancel) { failure = nil; alarms.error = nil }
        } message: { Text(failure ?? alarms.error ?? "") }
        .onAppear {
            voiceID = editing?.voiceID ?? alarms.voice(for: character.id)?.id ?? CharacterAlarm.systemSoundID
            title = editing?.title ?? "\(character.name)的提醒"
            if let editing { mode = 1; clockTime = editing.date }
        }
        .onDisappear { alarms.stopPreview() }
    }
}

struct CharacterAlarmsPage: View {
    @ObservedObject var alarms: CharacterAlarmStore
    let characters: [CompanionCharacter]
    @State private var editor: AlarmEditorSelection?

    var body: some View {
        WorldPage {
            HStack {
                PageHeading(eyebrow: "A LITTLE REMINDER", title: "等你醒来", subtitle: "把约好的时间，交给喜欢的角色。")
                Spacer(minLength: 0)
                AppearanceToggle()
            }
            ForEach(characters) { character in
                Button { editor = AlarmEditorSelection(character: character) } label: {
                    HStack(spacing: 13) {
                        CharacterAvatar(character: character, size: 48)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(character.name)的闹钟").font(.headline)
                            Text(alarms.voice(for: character.id) == nil ? "选择时间 · 系统提示音" : "选择时间和语音").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(AppPalette.accent)
                    }.worldCard()
                }.buttonStyle(.plain).accessibilityIdentifier("newAlarm-\(character.id)")
            }
            Text("已安排 \(alarms.snapshot.alarms.count) 个提醒").font(.headline)
            if alarms.snapshot.alarms.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "alarm").font(.system(size: 32)).foregroundStyle(AppPalette.accent)
                    Text("还没有约好的时间").font(.headline)
                    Text("可以单独设置闹钟，也可以在开始陪伴时开启到点语音。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 24).worldCard()
            }
            ForEach(alarms.snapshot.alarms) { alarm in
                let character = CharacterCatalog.resolve(alarm.characterID, in: characters)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(alarm.date, format: .dateTime.hour().minute()).font(.system(size: 30, weight: .medium, design: .rounded))
                        Spacer()
                        Text(alarm.backend == .alarmKit ? "系统闹钟" : "通知提醒").font(.caption).foregroundStyle(AppPalette.accent)
                    }
                    Text(alarm.title).font(.headline)
                    if alarms.ringingIDs.contains(alarm.id) {
                        Label("正在响铃", systemImage: "bell.fill").foregroundStyle(AppPalette.accent)
                            .accessibilityIdentifier("ringingAlarm-\(alarm.id)")
                    } else if alarm.date <= Date() {
                        Text("已到提醒时间").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(alarm.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text(alarm.usesSystemSound ? "系统提示音" : alarms.voices.first { $0.id == alarm.voiceID }?.title ?? "语音提醒").font(.subheadline)
                    HStack {
                        if alarm.sessionID == nil {
                            Button("修改") { editor = AlarmEditorSelection(character: character, alarm: alarm) }
                                .accessibilityIdentifier("editAlarm-\(alarm.id)")
                        } else {
                            Text("随本轮陪伴结束而取消").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(alarms.ringingIDs.contains(alarm.id) ? "停止响铃" : "取消提醒", role: .destructive) { alarms.cancel(alarm) }
                            .accessibilityIdentifier("cancelAlarm-\(alarm.id)")
                    }.font(.subheadline).disabled(alarms.busy)
                }.worldCard()
            }
            Text(alarms.deliveryExplanation).font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editor) { selection in
            NavigationStack {
                CharacterAlarmEditor(alarms: alarms, character: selection.character, editing: selection.alarm)
            }
        }
        .task { await alarms.refresh() }
        .alert("角色提醒", isPresented: Binding(get: { editor == nil && alarms.error != nil }, set: { if !$0 { alarms.error = nil } })) {
            Button("知道了", role: .cancel) { alarms.error = nil }
        } message: { Text(alarms.error ?? "") }
    }
}

private struct AlarmEditorSelection: Identifiable {
    let id = UUID()
    let character: CompanionCharacter
    var alarm: CharacterAlarm?
}

