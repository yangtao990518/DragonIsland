import Foundation

/// Home-page photos are independent of identity avatars and island artwork.
struct CharacterArtworkPreferences: Codable, Equatable {
    var selections: [String: String] = [:]

    func selected(for character: CompanionCharacter) -> CharacterArtwork {
        character.artwork(id: selections[character.id])
    }
    mutating func select(_ artworkID: String, for character: CompanionCharacter) {
        guard character.availableArtworks.contains(where: { $0.id == artworkID }) else { return }
        selections[character.id] = artworkID
    }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "characterWorldArtworks"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "characterWorldArtworks")
    }
}
