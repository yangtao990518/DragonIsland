import Foundation

struct SurvivorHD2DMonster: Codable, Sendable {
    let id: String
    let duration: Double
    let release: Double
    let kind: String
    let effect: String?
}
struct SurvivorHD2DDeath: Codable, Identifiable, Sendable {
    var clipID: String? = nil
    var frameTime: Double? = nil
    let id: UInt64
    let variant: String
    let position: SurvivorVector
    let facingLeft: Bool
    let born: Double
}
