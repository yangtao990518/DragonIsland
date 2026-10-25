import ActivityKit
import Combine
import Foundation
import UIKit

@MainActor
final class CompanionStore: ObservableObject {
    @Published private(set) var session: CompanionSession?
    @Published private(set) var busy = false
    @Published var notice: String?
    @Published private(set) var motionTestStatus: String?
    private var motionTask: Task<Void, Never>?
    private var motionBackgroundTask: UIBackgroundTaskIdentifier = .invalid
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
        cancelMotionTest()
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
        let state = CompanionSession(minutes: minutes)
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

    func scheduleMotionTest(_ motion: CompanionMotion) {
        guard !busy, let current = activity, !current.content.state.hasExpired() else { return }
        cancelMotionTest()
        motionBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "mAIverseMotionSample") { [weak self] in
            Task { @MainActor in
                self?.motionTestStatus = "系统已结束这次测试，请重新触发。"
                self?.cancelMotionTest()
            }
        }
        guard motionBackgroundTask != .invalid else {
            motionTestStatus = "无法安排延后测试，可在展开态点招呼或心情观察短动作。"
            return
        }
        let activityID = current.id
        motionTestStatus = "5 秒后发送\(motion.title)小样，请现在回到桌面。"
        motionTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.activity?.id == activityID else { return }
            await self.performMotion(motion)
            self.motionTestStatus = "已发送一次\(motion.title)更新；动画是否播放由系统决定。"
            self.cancelMotionTest()
        }
    }

    private func cancelMotionTest() {
        motionTask?.cancel()
        motionTask = nil
        if motionBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(motionBackgroundTask)
            motionBackgroundTask = .invalid
        }
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
