import Foundation

enum HomeButtonStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case fantasy, candy
    var id: String { rawValue }
    var title: String { self == .fantasy ? "A · 幻想徽章" : "B · 糖果可爱" }
    var assetPrefix: String { self == .fantasy ? "HomeButtonFantasy" : "HomeButtonCandy" }
}

enum HomeShortcutKind: String, CaseIterable, Identifiable, Sendable {
    case actions, scene, island
    var id: String { rawValue }
    var title: String {
        switch self { case .actions: return "动作"; case .scene: return "场景"; case .island: return "预览" }
    }
    var accessibilityTitle: String { self == .island ? "灵动岛预览" : title }
    var assetSuffix: String {
        switch self { case .actions: return "Actions"; case .scene: return "Scene"; case .island: return "Island" }
    }
}

/// A style belongs to a character, never to the global app appearance.
struct CharacterHomeButtonPreferences: Codable, Equatable {
    var selections: [String: String] = [:]
    func style(for characterID: String) -> HomeButtonStyle {
        selections[characterID].flatMap(HomeButtonStyle.init(rawValue:)) ?? .fantasy
    }
    mutating func select(_ style: HomeButtonStyle, for characterID: String) {
        guard !characterID.isEmpty else { return }
        selections[characterID] = style.rawValue
    }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "characterHomeButtonStyles"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "characterHomeButtonStyles")
    }
}
