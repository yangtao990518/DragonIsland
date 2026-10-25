import ActivityKit
import Combine
import Foundation

@MainActor
final class CompanionStore: ObservableObject {
    @Published private(set) var session: CompanionSession?
    @Published private(set) var busy = false
    @Published var notice: String?
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
    }

    private func attach(_ current: Activity<DragonAttributes>) {
        session = current.content.state
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
                attributes: DragonAttributes(companionName: "小白", sessionID: UUID()),
                content: ActivityContent(state: state, staleDate: state.endsAt),
                pushType: nil
            )
            attach(created)
        } catch {
            notice = "实时活动启动失败：\(error.localizedDescription)\n请确认签名保留了 Widget 扩展，并已允许实时活动。"
        }
    }

    func greet() async { await mutate(greeting: true) }
    func changeMood() async { await mutate(greeting: false) }

    private func mutate(greeting: Bool) async {
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
        if greeting { state.greet() } else { state.cycleMood() }
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
