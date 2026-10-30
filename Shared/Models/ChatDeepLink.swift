import Foundation

enum ChatDeepLink {
    static let pendingKey = "pendingChatConversationID"
    static let notificationName = "maiverse.open-chat"
    static func url(_ id: UUID) -> URL { URL(string: "dragonisle://chat/\(id.uuidString)")! }
    static func conversationID(_ url: URL) -> UUID? {
        guard url.scheme == "dragonisle", url.host == "chat", url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
