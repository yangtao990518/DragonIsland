import ActivityKit
import Combine
import Foundation
import UIKit

@MainActor
final class CompanionStore: ObservableObject {
    let alarms = CharacterAlarmStore()
    @Published private var characterMotionSettings = MotionSettings.loadCharacters()
    private let legacyMotionSettings = MotionSettings.load()
    var motionSettings: MotionSettings { settings(for: displayCharacter) }
    func settings(for character: CompanionCharacter) -> MotionSettings {
        characterMotionSettings[character.id] ?? legacyMotionSettings
    }
    @Published private(set) var islandScene = IslandScene.load()
    @Published private(set) var session: CompanionSession?
    @Published private(set) var busy = false
    @Published var notice: String?
    let characters = CharacterCatalog.load()
    @Published private(set) var selectedCharacterID = UserDefaults.standard.string(forKey: "selectedCharacterID") ?? "xiaobai"
    @Published private(set) var activeCharacterID: String?

    var selectedCharacter: CompanionCharacter { CharacterCatalog.resolve(selectedCharacterID, in: characters) }
    var displayCharacter: CompanionCharacter {
        CharacterCatalog.resolve(activeCharacterID ?? selectedCharacterID, in: characters)
    }

    func select(_ character: CompanionCharacter) {
        guard session == nil, characters.contains(where: { $0.id == character.id }) else { return }
        selectedCharacterID = character.id
        UserDefaults.standard.set(character.id, forKey: "selectedCharacterID")
    }
    private var activity: Activity<DragonAttributes>?
    private var contentTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    init() { restore() }

    func restore() {
        let candidates = Activity<DragonAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        guard let current = candidates.sorted(by: {
            $0.content.state.startedAt > $1.content.state.startedAt
        }).first else {
            clear()
            return
        }
        attach(current)
    }

    private func clear() {
        contentTask?.cancel()
        stateTask?.cancel()
        activity = nil
        session = nil
        activeCharacterID = nil
    }

    private func attach(_ current: Activity<DragonAttributes>) {
        session = current.content.state
        activeCharacterID = current.attributes.characterID ?? CompanionCharacter.xiaobai.id
        if activity?.id == current.id { return }
        contentTask?.cancel()
        stateTask?.cancel()
        activity = current
        contentTask = Task { [weak self] in
            for await content in current.contentUpdates {
                guard !Task.isCancelled, self?.activity?.id == current.id else { return }
                self?.session = content.state
            }
        }
        stateTask = Task { [weak self] in
            for await state in current.activityStateUpdates {
                guard !Task.isCancelled, self?.activity?.id == current.id else { return }
                if state == .ended || state == .dismissed {
                    self?.clear()
                    return
                }
            }
        }
    }

    func start(minutes: Int) async {
        guard !busy else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            notice = "请在 iPhone 设置中允许本 App 的实时活动。"
            return
        }
        busy = true
        defer { busy = false }
        notice = nil
        let voicePreference = alarms.preference(for: selectedCharacter.id)
        if voicePreference.enabled {
            do { try await alarms.authorize() }
            catch { notice = error.localizedDescription; return }
        }
        do {
            for previous in alarms.snapshot.alarms where previous.sessionID != nil {
                try alarms.cancel(id: previous.id)
            }
            for previous in Activity<DragonAttributes>.activities {
                try alarms.cancel(id: previous.attributes.sessionID)
            }
        } catch { notice = "旧提醒未能取消，请稍后重试：\(error.localizedDescription)"; return }
        // A previous stale session must not leave duplicate islands behind.
        for previous in Activity<DragonAttributes>.activities {
            await previous.end(previous.content, dismissalPolicy: .immediate)
        }
        clear()
        var state = CompanionSession(minutes: minutes)
        state.islandSceneID = islandScene.rawValue
        state.automaticMotionPlan = settings(for: selectedCharacter).plan(seed: Int.random(in: 0..<2), character: selectedCharacter)
        state.motionEpoch = state.startedAt
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-live-motion") {
            // Reproducible system-video QA: includes both directions and rolls.
            state.automaticMotionPlan = 6
            if ProcessInfo.processInfo.arguments.contains("--record-motion-metadata"),
               let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let legs = MotionTimeline.shared?.plans.first(where: { $0.id == 6 })?.legs ?? []
                let walkingSlots = legs.filter { $0.action == "walk" }.map { $0.start }
                let rollingSlots = legs.filter { $0.action == "roll" }.map { $0.start }
                let data: [String: Any] = ["epoch": state.startedAt.timeIntervalSince1970, "plan": 6, "fps": 30,
                                          "walkingSlots": walkingSlots, "walkingDuration": 10,
                                          "rollingSlots": rollingSlots, "rollingDuration": 5,
                                          "scene": islandScene.rawValue]
                if let json = try? JSONSerialization.data(withJSONObject: data) {
                    try? json.write(to: documents.appendingPathComponent("motion-capture.json"), options: .atomic)
                }
            }
        }
        #endif
        do {
            let sessionID = UUID()
            let created = try Activity.request(
                attributes: DragonAttributes(companionName: selectedCharacter.name, sessionID: sessionID,
                                             characterID: selectedCharacter.id),
                content: ActivityContent(state: state, staleDate: state.endsAt),
                pushType: nil
            )
            if voicePreference.enabled {
                do {
                    let soundID = alarms.voice(for: selectedCharacter.id)?.id ?? CharacterAlarm.systemSoundID
                    let alarm = CharacterAlarm(id: sessionID, characterID: selectedCharacter.id, voiceID: soundID,
                        title: "\(selectedCharacter.name) · 陪伴时间到啦", date: state.endsAt, sessionID: sessionID)
                    try await alarms.schedule(alarm)
                } catch {
                    await created.end(created.content, dismissalPolicy: .immediate)
                    throw error
                }
            }
            attach(created)
        } catch {
            notice = "本轮未能启动：\(error.localizedDescription)\n请检查实时活动、提醒权限，以及签名是否保留 Widget 扩展。"
        }
    }

    func greet() async { await mutate { $0.greet() } }
    func changeMood() async { await mutate { $0.cycleMood() } }
    func performMotion(_ motion: CompanionMotion) async { await mutate { $0.performMotion(motion) } }

    func setMotionSettings(_ value: MotionSettings) async {
        await setMotionSettings(value, for: displayCharacter)
    }

    func setMotionSettings(_ value: MotionSettings, for character: CompanionCharacter) async {
        guard !busy else { return }
        characterMotionSettings[character.id] = value
        MotionSettings.saveCharacters(characterMotionSettings)
        guard session != nil, displayCharacter.id == character.id else { return }
        await mutate {
            $0.automaticMotionPlan = value.plan(seed: 0, character: character)
            $0.motionEpoch = Date()
            $0.revision += 1
        }
    }

    func setIslandScene(_ value: IslandScene) async {
        guard !busy else { return }
        islandScene = value
        value.save()
        await mutate {
            $0.islandSceneID = value.rawValue
            $0.revision += 1
        }
    }

    private func mutate(_ update: (inout CompanionSession) -> Void) async {
        guard !busy, let current = activity else { return }
        busy = true
        defer { busy = false }
        var state = current.content.state
        if state.hasExpired() {
            await current.end(current.content, dismissalPolicy: .immediate)
            if activity?.id == current.id { clear() }
            notice = "这一轮结束啦，可以再开始一轮。"
            return
        }
        update(&state)
        await current.update(ActivityContent(state: state, staleDate: state.endsAt))
        if activity?.id == current.id { session = state }
    }

    func finish() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            for alarm in alarms.snapshot.alarms where alarm.sessionID != nil { try alarms.cancel(id: alarm.id) }
            for current in Activity<DragonAttributes>.activities { try alarms.cancel(id: current.attributes.sessionID) }
        } catch { notice = "提醒未能取消，本轮暂未结束：\(error.localizedDescription)"; return }
        for current in Activity<DragonAttributes>.activities {
            await current.end(current.content, dismissalPolicy: .immediate)
        }
        clear()
    }
}


