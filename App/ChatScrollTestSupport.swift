#if DEBUG
import Foundation

/// Long, synthetic conversations in an explicitly isolated UI-test store only.
@MainActor
enum ChatScrollTestSupport {
    static func seed(_ store: ChatStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--maiverse-capture"), arguments.contains("--chat-scroll-tests"),
              let flag = arguments.firstIndex(of: "--chat-test-store"),
              arguments.indices.contains(flag + 1), UUID(uuidString: arguments[flag + 1]) != nil,
              store.ready, store.history.conversations.isEmpty,
              let first = store.characters.first else { return }
        do {
            var history = ChatHistory()
            let available = Set(store.characters.map(\.id))
            for kind in [ChatKind.direct, .group] {
                let members = kind == .direct ? [first] : store.characters
                let ids = members.map(\.id)
                let id = try history.create(kind: kind, name: "滚动测试群组", characterIDs: ids, availableIDs: available)
                guard let index = history.conversations.firstIndex(where: { $0.id == id }) else { continue }
                for turn in 0..<40 {
                    var user = ChatMessage.user(turn == 0 ? "SCROLL_FIRST_\(kind.rawValue)" : "历史消息 \(turn)", recipients: ids)
                    user.delivery = .sent
                    history.conversations[index].messages.append(user)
                    for (offset, character) in members.enumerated() {
                        let text = turn == 39 && offset == members.count - 1
                            ? "SCROLL_LATEST_\(kind.rawValue)" : "历史回复 \(turn) · \(character.name)"
                        history.conversations[index].messages.append(.reply(text, character: character, to: user.id))
                    }
                }
            }
            try ChatHistoryFile.standard.save(history)
            store.reload()
        } catch { store.error = "滚动测试记录准备失败。" }
    }
}
#endif
