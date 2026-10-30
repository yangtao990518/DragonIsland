import ActivityKit
import Foundation

struct ChatReminderAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let preview: String
        let unreadCount: Int
        let sentAt: Date
    }
    let conversationID: UUID
    let characterID: String
    let characterName: String
}
