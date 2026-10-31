import Foundation
import CryptoKit

struct ChatToolCall: Codable, Equatable, Sendable {
    struct Function: Codable, Equatable, Sendable { var name: String; var arguments: String }
    var id: String
    var type = "function"
    var function: Function
    func arguments() throws -> [String: String] {
        guard type == "function", !id.isEmpty, id.count <= 200, function.arguments.utf8.count <= 8192,
              let data = function.arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode([String: String].self, from: data),
              let definition = ChatTools.all.first(where: { $0.name == function.name }),
              Set(args.keys) == Set(definition.fields.keys), args.values.allSatisfy({ $0.count <= 500 }) else { throw AIChatError.invalidResponse }
        return args
    }
    func fingerprint(characterID: String) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let canonical = try encoder.encode(arguments())
        return SHA256.hash(data: Data((characterID + ":" + function.name + ":").utf8) + canonical)
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct ChatToolReceipt: Codable, Equatable, Sendable {
    let fingerprint: String
    let characterID: String
    let name: String
    var result: String? = nil
    var sticker: CharacterSticker? = nil
    func validate() throws {
        guard fingerprint.count == 64, !characterID.isEmpty,
              ChatTools.all.contains(where: { $0.name == name }), (result?.count ?? 0) <= 6000 else { throw ChatError.invalidHistory }
        try sticker?.validate()
        if let sticker { guard name == "send_sticker", sticker.characterID == characterID else { throw ChatMediaError.invalid } }
    }
}

enum ChatTools {
    struct Definition: Sendable {
        let name: String; let description: String; let fields: [String: String]
        var schema: [String: Any] {
            ["type": "function", "function": ["name": name, "description": description,
                "parameters": ["type": "object", "properties": fields.mapValues { ["type": "string", "description": $0] },
                               "required": fields.keys.sorted(), "additionalProperties": false]]]
        }
    }
    static let all: [Definition] = [
        .init(name: "send_sticker", description: "发送自己表情库中的一个表情；每次回复最多一个。", fields: ["sticker_id": "表情 UUID"]),
        .init(name: "app_state", description: "读取当前角色可用的动作、图片、场景、陪伴和自己的闹钟；不读取聊天或其他角色资料。", fields: [:]),
        .init(name: "select_character", description: "选择自己作为主页角色；已有陪伴时不能切换。", fields: [:]),
        .init(name: "start_companion", description: "邀请自己上岛开始陪伴。已有陪伴时不覆盖。需用户确认。", fields: ["minutes": "1 到 1440 的整数分钟"]),
        .init(name: "finish_companion", description: "结束自己的当前陪伴及其关联提醒。需用户确认。", fields: [:]),
        .init(name: "set_scene", description: "更改灵动岛场景；只能使用 app_state 返回的场景 ID。需用户确认。", fields: ["scene_id": "场景 ID"]),
        .init(name: "set_artwork", description: "设置自己在我的世界的展示图。需用户确认。", fields: ["artwork_id": "图片 ID"]),
        .init(name: "set_actions", description: "替换自己的自动活动设置，按现有时间表轮换，不是立刻播放。需用户确认。", fields: ["actions": "英文逗号分隔：walk,roll,ride,pet_walk,dance1,dance2；空字符串表示待机"]),
        .init(name: "create_alarm", description: "为自己新增未来闹钟，使用系统默认声音。需用户确认和系统授权。", fields: ["title": "闹钟标题，最多 80 字", "date": "带时区的 ISO8601 日期时间，例如 2026-10-30T21:00:00+08:00"]),
        .init(name: "cancel_alarm", description: "取消自己的普通闹钟；不能取消陪伴关联提醒。需用户确认。", fields: ["alarm_id": "闹钟 UUID"])
    ]
    static func allowed(for request: ChatReplyRequest) -> [Definition] {
        guard request.proactiveDeliveryDate == nil, request.memoryExtraction == nil else { return [] }
        return all.filter { $0.name == "send_sticker" ? request.profile?.automaticStickers == true && !request.stickers.isEmpty : request.profile?.appControl == true }
    }
}

/// Only an App implementation may execute commands. The Widget and domain never receive credentials or UI handles.
typealias ChatAppToolHandler = @MainActor @Sendable (String, ChatToolCall, [String: String]) async throws -> String
