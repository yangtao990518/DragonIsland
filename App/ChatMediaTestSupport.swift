#if DEBUG
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Synthetic UI-test fixtures only. No personal photos or API calls are used by simulator tests.
@MainActor
enum ChatMediaTestSupport {
    static func seed(_ store: ChatStore) {
        guard ProcessInfo.processInfo.arguments.contains("--chat-media-tools-tests"), store.history.stickers == nil else { return }
        do {
            let png = try image(gif: false); let gif = try image(gif: true)
            _ = store.addSticker(data: png, characterID: "xiaobai", name: "小白静态测试", meaning: "打招呼")
            _ = store.addSticker(data: gif, characterID: "xiaobai", name: "小白动态测试", meaning: "开心")
            _ = store.addSticker(data: png, characterID: "dafeiyu", name: "大肥鱼静态测试", meaning: "高兴")
            var preferences = store.configuration
            for character in store.characters {
                var profile = preferences.profile(for: character)
                profile.appControl = true; profile.automaticStickers = true
                preferences.characters[character.id] = profile
            }
            _ = store.saveConfiguration(preferences)
            if let id = store.create(kind: .direct, characterIDs: ["xiaobai"]) { _ = store.attach(data: png, in: id) }
        } catch { store.error = "测试素材准备失败。" }
    }
    static func image(gif: Bool) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, (gif ? UTType.gif : .png).identifier as CFString, gif ? 2 : 1, nil) else { throw ChatMediaError.invalid }
        for index in 0..<(gif ? 2 : 1) {
            guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ChatMediaError.invalid }
            context.setFillColor(CGColor(red: index == 0 ? 0.2 : 0.7, green: 0.3, blue: 0.9, alpha: 1))
            context.fillEllipse(in: CGRect(x: 6, y: 6, width: 52, height: 52))
            guard let image = context.makeImage() else { throw ChatMediaError.invalid }
            CGImageDestinationAddImage(destination, image, gif ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.3]] as CFDictionary : nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw ChatMediaError.invalid }
        return data as Data
    }
}

struct ChatMediaTestProvider: ChatReplyProvider {
    func reply(to request: ChatReplyRequest) async throws -> String { "收到消息。" }
    func reply(to request: ChatReplyRequest, onPartial: @escaping @Sendable (String) async -> Void, onTool: @escaping ChatToolHandler) async throws -> String {
        if request.userMessage.text.contains("测试操作") || request.userMessage.text.contains("test-action") {
            let id = request.character.availableArtworks.last?.id ?? "default"
            let args = String(decoding: try JSONEncoder().encode(["artwork_id": id]), as: UTF8.self)
            return try await onTool(.init(id: "fixture-action", function: .init(name: "set_artwork", arguments: args)))
        }
        if request.userMessage.text.contains("测试表情") || request.userMessage.text.contains("test-sticker"), let sticker = request.stickers.first(where: { $0.asset.animated }) {
            let args = String(decoding: try JSONEncoder().encode(["sticker_id": sticker.id.uuidString]), as: UTF8.self)
            return try await onTool(.init(id: "fixture-sticker", function: .init(name: "send_sticker", arguments: args)))
        }
        return "收到消息。"
    }
}
#endif
