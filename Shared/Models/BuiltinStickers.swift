import Foundation

enum BuiltinStickerCatalog {
    private struct Catalog: Decodable { let version: Int; let stickers: [CharacterSticker] }
    static func load(bundle: Bundle = .main) -> [CharacterSticker] {
        guard let url = bundle.url(forResource: "BuiltinStickers", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.version == 1, Set(catalog.stickers.map(\.id)).count == catalog.stickers.count,
              catalog.stickers.allSatisfy({ sticker in
                  do { try sticker.validate(); return true } catch { return false }
              }) else { return [] }
        return catalog.stickers
    }
}
