import SwiftUI

@MainActor
final class ChatAppTools: ObservableObject {
    struct Approval: Identifiable { let id: UUID; let title: String; let detail: String }
    @Published var approval: Approval?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?
    private let companion: CompanionStore
    var permission: (String) -> Bool = { _ in false }
    init(companion: CompanionStore) { self.companion = companion }

    func resolve(_ approved: Bool) {
        timeout?.cancel(); timeout = nil
        let waiting = continuation; continuation = nil; approval = nil
        waiting?.resume(returning: approved)
    }
    private func confirm(title: String, detail: String) async -> Bool {
        guard continuation == nil, !Task.isCancelled else { return false }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiting in
                continuation = waiting; approval = .init(id: id, title: title, detail: detail)
                timeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 90_000_000_000)
                    guard !Task.isCancelled, self?.approval?.id == id else { return }
                    self?.resolve(false)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in if self?.approval?.id == id { self?.resolve(false) } }
        }
    }

    func execute(characterID: String, call: ChatToolCall, args: [String: String]) async throws -> String {
        guard permission(characterID), let character = companion.characters.first(where: { $0.id == characterID }) else { return "未执行：角色操作权限已关闭。" }
        let name = call.function.name
        if name == "app_state" {
            let formatter = ISO8601DateFormatter()
            let value: [String: Any] = [
                "character": ["id": character.id, "name": character.name],
                "selectedCharacterID": companion.selectedCharacterID,
                "activeCharacterID": companion.activeCharacterID ?? "",
                "busy": companion.busy,
                "sessionEndsAt": companion.session.map { formatter.string(from: $0.endsAt) } ?? "",
                "currentScene": companion.islandScene.rawValue,
                "scenes": IslandScene.allCases.map { ["id": $0.rawValue, "title": $0.title] },
                "artworks": character.availableArtworks.map { ["id": $0.id, "title": $0.title] },
                "selectedArtworkID": companion.worldArtwork(for: character).id,
                "availableActions": ["walk", "roll"] + (character.motionProfile?.dailyActions ?? []).map(\.id),
                "enabledActions": enabledActions(for: character),
                "actionPlayback": "自动活动按既有时间表轮换；配置动作不会立即播放。",
                "alarms": companion.alarms.snapshot.alarms.filter { $0.characterID == characterID && $0.sessionID == nil }
                    .map { ["id": $0.id.uuidString, "title": $0.title, "date": formatter.string(from: $0.date)] }
            ]
            return String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self)
        }
        guard !companion.busy else { return "未执行：App 正在处理另一项操作，请稍后再试。" }
        let detail: String
        switch name {
        case "select_character": detail = "将「我的世界」当前角色切换为\(character.name)。已有陪伴时不会切换。"
        case "start_companion":
            guard let minutes = Int(args["minutes"] ?? ""), (1...1440).contains(minutes) else { return "未执行：陪伴时长必须是 1～1440 分钟。" }
            detail = "邀请\(character.name)上岛陪伴 \(minutes) 分钟。启用了提醒时会使用现有提醒设置。"
        case "finish_companion": detail = "结束\(character.name)的当前陪伴，并取消这轮陪伴关联的提醒。"
        case "set_scene":
            guard let scene = IslandScene(rawValue: args["scene_id"] ?? "") else { return "未执行：场景不存在。" }
            detail = "灵动岛场景更改为「\(scene.title)」。这项设置影响当前陪伴。"
        case "set_artwork":
            guard let artwork = character.availableArtworks.first(where: { $0.id == args["artwork_id"] }) else { return "未执行：图片不属于该角色。" }
            detail = "\(character.name)在「我的世界」的展示图更改为「\(artwork.title)」。"
        case "set_actions":
            let actions = actionIDs(args["actions"] ?? "")
            let supported = Set(["walk", "roll"] + (character.motionProfile?.dailyActions ?? []).map(\.id))
            guard actions.allSatisfy(supported.contains) else { return "未执行：包含当前角色不支持的动作。" }
            detail = "替换\(character.name)的自动活动设置为：\(actions.isEmpty ? "仅待机" : actions.joined(separator: "、"))。动作按既有时间表轮换，不会立即播放。"
        case "create_alarm":
            guard let date = ISO8601DateFormatter().date(from: args["date"] ?? ""), date > Date(),
                  date.timeIntervalSinceNow <= 366 * 86400, let title = args["title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80 else { return "未执行：请提供未来一年内、带时区的时间和 1～80 字标题。" }
            detail = "新增\(character.name)的闹钟「\(title)」\n\(date.formatted(date: .abbreviated, time: .shortened))\n使用系统默认声音。"
        case "cancel_alarm":
            guard let id = UUID(uuidString: args["alarm_id"] ?? ""), let alarm = companion.alarms.snapshot.alarms.first(where: { $0.id == id && $0.characterID == characterID && $0.sessionID == nil }) else { return "未执行：未找到属于该角色的普通闹钟。" }
            detail = "取消\(character.name)的闹钟「\(alarm.title)」。"
        default: return "未执行：不支持的操作。"
        }
        guard await confirm(title: "\(character.name)想操作 App", detail: detail) else { return "用户未确认，操作未执行。" }
        try Task.checkCancellation()
        // Recheck live state and permissions after the user has read the concrete change.
        guard permission(characterID), !companion.busy else { return "未执行：权限或 App 状态发生变化。" }
        switch name {
        case "select_character":
            guard companion.session == nil else { return "未执行：请先结束当前陪伴。" }
            companion.select(character)
            return companion.selectedCharacterID == characterID ? "已切换到\(character.name)。" : "切换未完成。"
        case "start_companion":
            guard companion.session == nil else { return "未执行：已经有陪伴进行中，不会覆盖。" }
            companion.select(character); await companion.start(minutes: Int(args["minutes"]!)!)
            return companion.activeCharacterID == characterID && companion.session != nil ? "\(character.name)已开始陪伴。" : "启动未完成，请在我的世界检查实时活动及提醒权限。"
        case "finish_companion":
            guard companion.session != nil, companion.activeCharacterID == characterID else { return "未执行：没有属于你的陪伴，不能结束其他角色的陪伴。" }
            await companion.finish()
            return companion.session == nil ? "陪伴已结束。" : "结束未完成，请检查提醒状态。"
        case "set_scene":
            guard companion.activeCharacterID == nil || companion.activeCharacterID == characterID else { return "未执行：不能更改其他角色当前陪伴的场景。" }
            let scene = IslandScene(rawValue: args["scene_id"]!)!
            await companion.setIslandScene(scene)
            return companion.islandScene == scene ? "场景已更改。" : "场景更改未完成。"
        case "set_artwork":
            companion.selectWorldArtwork(args["artwork_id"]!, for: character)
            return companion.worldArtwork(for: character).id == args["artwork_id"] ? "展示图已更改。" : "展示图更改未完成。"
        case "set_actions":
            let ids = Set(actionIDs(args["actions"]!))
            let value = MotionSettings(walk: ids.contains("walk"), roll: ids.contains("roll"), ride: ids.contains("ride"),
                petWalk: ids.contains("pet_walk"), dance1: ids.contains("dance1"), dance2: ids.contains("dance2"))
            await companion.setMotionSettings(value, for: character)
            return companion.settings(for: character) == value ? "自动活动设置已保存，按现有时间表轮换。" : "动作设置未完成。"
        case "create_alarm":
            guard let date = ISO8601DateFormatter().date(from: args["date"]!), date > Date() else { return "未执行：确认期间时间已过，请重新指定。" }
            let alarm = CharacterAlarm(id: UUID(), characterID: characterID, voiceID: CharacterAlarm.systemSoundID,
                title: args["title"]!, date: date)
            _ = try await companion.alarms.schedule(alarm)
            return "已创建闹钟，ID：\(alarm.id.uuidString)，时间：\(args["date"]!)。"
        case "cancel_alarm":
            guard let id = UUID(uuidString: args["alarm_id"]!), companion.alarms.snapshot.alarms.contains(where: { $0.id == id && $0.characterID == characterID && $0.sessionID == nil }) else { return "闹钟已不存在，未执行取消。" }
            try companion.alarms.cancel(id: id)
            return "闹钟已取消。"
        default: return "未执行。"
        }
    }
    private func actionIDs(_ text: String) -> [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    private func enabledActions(for character: CompanionCharacter) -> [String] {
        let value = companion.settings(for: character)
        guard value.automatic else { return [] }
        return [("walk", value.walk), ("roll", value.roll), ("ride", value.ride), ("pet_walk", value.petWalk),
                ("dance1", value.dance1), ("dance2", value.dance2)].filter(\.1).map(\.0)
    }
}

struct ChatAppApprovalView: View {
    @ObservedObject var tools: ChatAppTools
    let approval: ChatAppTools.Approval
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(approval.detail) }
                Button("确认执行") { tools.resolve(true) }.accessibilityIdentifier("approveChatAppAction")
                Button("不执行", role: .cancel) { tools.resolve(false) }.accessibilityIdentifier("declineChatAppAction")
            }.navigationTitle(approval.title).navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large])
    }
}
