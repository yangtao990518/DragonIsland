import ActivityKit
import Foundation

struct DragonAttributes: ActivityAttributes {
    typealias ContentState = CompanionSession
    let companionName: String
    let sessionID: UUID
    // Optional so activities created before the character catalog still decode.
    let characterID: String?

    init(companionName: String, sessionID: UUID, characterID: String? = nil) {
        self.companionName = companionName
        self.sessionID = sessionID
        self.characterID = characterID
    }
}
