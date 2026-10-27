import Foundation

struct CompanionCharacter: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let introduction: String
    let origin: String
    let chibiAsset: String
    let portraitAsset: String
    let heroAsset: String
    let chibiSource: String
    let standingSource: String
    var motion: CharacterMotionProfile? = nil

    var avatarAsset: String { portraitAsset + "Avatar" }
    var motionProfile: CharacterMotionProfile? {
        motion ?? (id == "xiaobai" ? .xiaobai : nil)
    }

    static let xiaobai = CompanionCharacter(
        id: "xiaobai", name: "小白", subtitle: "白紫龙娘",
        introduction: "你忙你的，我就在这里。", origin: "ChatGPT 同人角色",
        chibiAsset: "XiaobaiChibi", portraitAsset: "XiaobaiStanding", heroAsset: "XiaobaiHero",
        chibiSource: "Art/xiaobai-chibi-v2.png", standingSource: "Art/xiaobai-standing.png"
    )
}

struct CharacterMotionProfile: Codable, Hashable, Sendable {
    let manifest: String
    let fontPrefix: String
    let assetPrefix: String
    let timelineResource: String
    var greetingFrames: [String]? = nil

    static let xiaobai = CharacterMotionProfile(manifest: "Art/MotionV4/manifest.json",
        fontPrefix: "mAIverse", assetPrefix: "Motion", timelineResource: "MotionTimeline",
        greetingFrames: ["Motion_idle_004", "Motion_idle_005", "Motion_idle_006", "Motion_idle_000"])
}

enum CharacterCatalog {
    static func load(from bundle: Bundle = .main) -> [CompanionCharacter] {
        guard let url = bundle.url(forResource: "Characters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let characters = try? decode(data) else { return [.xiaobai] }
        return characters
    }

    static func decode(_ data: Data) throws -> [CompanionCharacter] {
        let characters = try JSONDecoder().decode([CompanionCharacter].self, from: data)
        guard !characters.isEmpty, Set(characters.map(\.id)).count == characters.count,
              characters.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && !$0.chibiAsset.isEmpty
                  && !$0.portraitAsset.isEmpty && !$0.heroAsset.isEmpty }) else {
            throw CatalogError.invalidCharacters
        }
        return characters
    }

    static func resolve(_ id: String?, in characters: [CompanionCharacter]) -> CompanionCharacter {
        characters.first(where: { $0.id == id }) ?? characters.first ?? .xiaobai
    }

    enum CatalogError: Error { case invalidCharacters }
}

