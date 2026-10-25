import ActivityKit
import Combine
import Foundation
import UIKit

@MainActor
final class CompanionStore: ObservableObject {
    @Published private(set) var motionSettings = MotionSettings.load()
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
        // A previous stale session must not leave duplicate islands behind.
        for previous in Activity<DragonAttributes>.activities {
            await previous.end(previous.content, dismissalPolicy: .immediate)
        }
        clear()
        var state = CompanionSession(minutes: minutes)
        state.islandSceneID = islandScene.rawValue
        state.automaticMotionPlan = motionSettings.plan(seed: Int.random(in: 0..<2))
        state.motionEpoch = state.startedAt
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-live-motion") {
            // Reproducible system-video QA: includes both directions and rolls.
            state.automaticMotionPlan = 6
            if ProcessInfo.processInfo.arguments.contains("--record-motion-metadata"),
               let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let slots = MotionTimeline.shared?.plans.first(where: { $0.id == 6 })?.slots ?? []
                let walkingSlots = slots.indices.filter { slots[$0] == "walk" }.map { $0 * 5 }
                let data: [String: Any] = ["epoch": state.startedAt.timeIntervalSince1970, "plan": 6, "fps": 30,
                                          "walkingSlots": walkingSlots, "scene": islandScene.rawValue]
                if let json = try? JSONSerialization.data(withJSONObject: data) {
                    try? json.write(to: documents.appendingPathComponent("motion-capture.json"), options: .atomic)
                }
            }
        }
        #endif
        do {
            let created = try Activity.request(
                attributes: DragonAttributes(companionName: selectedCharacter.name, sessionID: UUID(),
                                             characterID: selectedCharacter.id),
                content: ActivityContent(state: state, staleDate: state.endsAt),
                pushType: nil
            )
            attach(created)
        } catch {
            notice = "实时活动启动失败：\(error.localizedDescription)\n请确认签名保留了 Widget 扩展，并已允许实时活动。"
        }
    }

    func greet() async { await mutate { $0.greet() } }
    func changeMood() async { await mutate { $0.cycleMood() } }
    func performMotion(_ motion: CompanionMotion) async { await mutate { $0.performMotion(motion) } }

    func setMotionSettings(_ value: MotionSettings) async {
        guard !busy else { return }
        motionSettings = value
        value.save()
        await mutate {
            $0.automaticMotionPlan = value.plan(seed: 0)
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
        for current in Activity<DragonAttributes>.activities {
            await current.end(current.content, dismissalPolicy: .immediate)
        }
        clear()
    }
}
