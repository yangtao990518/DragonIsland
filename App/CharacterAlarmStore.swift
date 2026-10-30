import ActivityKit
import AVFoundation
import Combine
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

enum VoiceAlarmError: LocalizedError {
    case permission, missingVoice, tooSoon, limit
    var errorDescription: String? {
        switch self {
        case .permission: return "没有获得提醒权限，请在系统设置中允许 mAIverse 使用闹钟或通知声音。此次提醒尚未设置。"
        case .missingVoice: return "这个角色的语音文件暂不可用，请重新选择。"
        case .tooSoon: return "请选择至少 5 秒后的时间。"
        case .limit: return "最多同时保留 20 个提醒，请先取消一些提醒。"
        }
    }
}

@MainActor
final class CharacterAlarmStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate, AVAudioPlayerDelegate {
    let voices = VoiceCatalog.load()
    @Published private(set) var snapshot = CharacterAlarmSnapshot.load()
    @Published private(set) var busy = false
    @Published private(set) var playingID: String?
    @Published private(set) var ringingIDs: Set<UUID> = []
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var updates: Task<Void, Never>?

    var usesAlarmKit: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    var deliveryExplanation: String {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .denied {
            return "闹钟权限已关闭，提醒可能无法响铃。请在系统设置中重新允许。"
        }
        #endif
        return usesAlarmKit ? "使用系统闹钟，到点由系统唤起提醒。首次使用需允许闹钟权限。"
        : "此系统版本使用通知语音提醒，会受静音、专注模式和通知声音设置影响，不会持续响铃。"
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            updates = Task { [weak self] in
                for await _ in AlarmManager.shared.alarmUpdates {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
        #endif
    }

    func preference(for characterID: String) -> CharacterVoicePreference {
        snapshot.preferences[characterID] ?? CharacterVoicePreference()
    }

    func voice(for characterID: String) -> CharacterVoice? {
        let available = VoiceCatalog.voices(for: characterID, in: voices)
        let id = preference(for: characterID).voiceID
        return available.first { $0.id == id } ?? available.first
    }

    func setPreference(characterID: String, enabled: Bool, voiceID: String?) {
        reload()
        snapshot.preferences[characterID] = CharacterVoicePreference(enabled: enabled, voiceID: voiceID)
        snapshot.save()
    }

    func refresh() async {
        guard !busy else { return }
        reload()
        let inspectedIDs = Set(snapshot.alarms.map(\.id))
        var liveIDs = Set<UUID>()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let systemAlarms = try AlarmManager.shared.alarms
                liveIDs = Set(systemAlarms.map(\.id))
                ringingIDs = Set(systemAlarms.filter { $0.state == .alerting }.map(\.id))
            }
            catch { return } // A temporary daemon error must not erase saved alarms.
        }
        #endif
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        guard !busy else { return }
        reload()
        let notificationIDs = Set(pending.map(\.identifier) + delivered.map { $0.request.identifier })
        snapshot.reconcile(inspectedIDs: inspectedIDs, systemAlarmIDs: liveIDs, notificationIDs: notificationIDs)
        snapshot.save()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--maiverse-capture"),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let report: [String: Any] = ["alarmKit": usesAlarmKit, "scheduledIDs": snapshot.alarms.map { $0.id.uuidString },
                "ringingIDs": ringingIDs.map(\.uuidString), "updatedAt": Date().timeIntervalSince1970]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) {
                try? data.write(to: documents.appendingPathComponent("alarm-system-state.json"), options: .atomic)
            }
        }
        #endif
    }

    func authorize() async throws {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            var status = AlarmManager.shared.authorizationState
            if status == .notDetermined { status = try await AlarmManager.shared.requestAuthorization() }
            guard status == .authorized else { throw VoiceAlarmError.permission }
            return
        }
        #endif
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        let settings = await center.notificationSettings()
        guard granted, settings.soundSetting == .enabled else { throw VoiceAlarmError.permission }
    }

    @discardableResult
    func schedule(_ alarm: CharacterAlarm, replacing old: CharacterAlarm? = nil) async throws -> CharacterAlarm {
        guard !busy else { throw VoiceAlarmError.limit }
        busy = true
        defer { busy = false }
        try await authorize()
        guard alarm.date.timeIntervalSinceNow >= 5 else { throw VoiceAlarmError.tooSoon }
        let voice = voices.first(where: { $0.id == alarm.voiceID && $0.characterID == alarm.characterID })
        if !alarm.usesSystemSound {
            guard let voice, Bundle.main.url(forResource: voice.file, withExtension: nil) != nil else {
                throw VoiceAlarmError.missingVoice
            }
        }
        reload()
        guard snapshot.alarms.count < 20 || old != nil else { throw VoiceAlarmError.limit }
        var saved = alarm
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: alarm.title))
            } else {
                alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: alarm.title),
                    stopButton: AlarmButton(text: "知道啦", textColor: .white, systemImageName: "checkmark"))
            }
            let attributes = AlarmAttributes<CharacterAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                metadata: CharacterAlarmMetadata(characterID: alarm.characterID, voiceID: alarm.voiceID,
                    alarmID: alarm.id.uuidString, title: alarm.title),
                tintColor: Color(red: 0.76, green: 0.67, blue: 0.94))
            // A fixed alarm fires at the same end date as the companion countdown.
            // No second countdown Live Activity competes with the character's island.
            let configuration = AlarmManager.AlarmConfiguration<CharacterAlarmMetadata>.alarm(
                schedule: .fixed(alarm.date), attributes: attributes,
                sound: alarm.usesSystemSound ? .default : .named(voice!.file))
            _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
            saved.backend = .alarmKit
        } else {
            try await scheduleNotification(alarm, voice: voice)
        }
        #else
        try await scheduleNotification(alarm, voice: voice)
        #endif
        if let old {
            do { try AlarmCancellation.cancel(id: old.id) }
            catch {
                let originalError = error
                do { try AlarmCancellation.cancel(id: alarm.id) }
                catch {
                    // Keep both records visible if the daemon rejects rollback too.
                    reload()
                    snapshot.alarms.append(saved)
                    snapshot.alarms.sort { $0.date < $1.date }
                    snapshot.save()
                    throw NSError(domain: "mAIverse.Alarm", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "系统未能完成闹钟替换，两个提醒均已保留在列表中。请返回列表逐个检查并取消。"])
                }
                throw originalError
            }
        }
        reload()
        snapshot.alarms.removeAll { $0.id == saved.id }
        snapshot.alarms.append(saved)
        snapshot.alarms.sort { $0.date < $1.date }
        snapshot.save()
        return saved
    }

    private func scheduleNotification(_ alarm: CharacterAlarm, voice: CharacterVoice?) async throws {
        let content = UNMutableNotificationContent()
        content.title = alarm.title
        content.body = alarm.usesSystemSound ? "约好的时间到啦。" : voice?.text ?? ""
        if alarm.usesSystemSound { content.sound = .default }
        else if let voice { content.sound = UNNotificationSound(named: UNNotificationSoundName(voice.file)) }
        content.userInfo = ["characterID": alarm.characterID, "alarmID": alarm.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, alarm.date.timeIntervalSinceNow), repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alarm.notificationID,
                                                                             content: content, trigger: trigger))
    }

    func cancel(_ alarm: CharacterAlarm) {
        do { try cancel(id: alarm.id) } catch { self.error = error.localizedDescription }
    }

    func cancel(id: UUID) throws {
        try AlarmCancellation.cancel(id: id)
        reload()
    }

    func play(_ voice: CharacterVoice) {
        if playingID == voice.id { stopPreview(); return }
        stopPreview()
        guard let url = Bundle.main.url(forResource: voice.file, withExtension: nil) else {
            error = VoiceAlarmError.missingVoice.localizedDescription; return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            audio.prepareToPlay()
            guard audio.play() else { throw VoiceAlarmError.missingVoice }
            player = audio
            playingID = voice.id
        } catch { self.error = error.localizedDescription; stopPreview() }
    }

    func stopPreview() {
        player?.stop()
        player = nil
        playingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stopPreview() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.error = "这条语音暂时无法播放，请重新选择。"
            self?.stopPreview()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["chatConversationID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            UserDefaults.standard.set(id.uuidString, forKey: ChatDeepLink.pendingKey)
            NotificationCenter.default.post(name: Notification.Name(ChatDeepLink.notificationName), object: id)
        }
    }

    private func reload() { snapshot = CharacterAlarmSnapshot.load() }
}

