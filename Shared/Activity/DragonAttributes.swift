import ActivityKit
import Foundation

struct DragonAttributes: ActivityAttributes {
    typealias ContentState = CompanionSession
    let companionName: String
    let sessionID: UUID
}
