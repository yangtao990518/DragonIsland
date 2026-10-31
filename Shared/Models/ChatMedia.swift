import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum ChatMediaError: LocalizedError {
    case invalid, tooLarge, missing, limit
    var errorDescription: String? {
        switch self {
        case .invalid: return "请选择有效的 PNG、JPEG 或 GIF 图片（最大 4096×4096，GIF 最长 20 秒）。"
        case .tooLarge: return "单个文件不能超过 10 MB。"
        case .missing: return "图片文件缺失或校验失败，请重新导入。"
        case .limit: return "每条消息最多 4 个附件，每位角色最多 100 个表情。"
        }
    }
}

/// Immutable content-addressed originals. A sticker is a semantic message, not an image alias.
struct ChatMediaAsset: Codable, Equatable, Hashable, Sendable {
    let sha256: String
    let fileExtension: String
    let width: Int
    let height: Int
    let frameCount: Int
    let duration: Double
    let byteCount: Int
    var filename: String { "\(sha256).\(fileExtension)" }
    var animated: Bool { frameCount > 1 }

    func validate() throws {
        guard sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              ["png", "jpg", "gif"].contains(fileExtension), (1...4096).contains(width), (1...4096).contains(height),
              (1...600).contains(frameCount), duration.isFinite, (0...20).contains(duration),
              (1...10 * 1024 * 1024).contains(byteCount), frameCount == 1 || fileExtension == "gif" else { throw ChatMediaError.invalid }
    }

    static func inspect(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw ChatMediaError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let ext = [UTType.png.identifier: "png", UTType.jpeg.identifier: "jpg", UTType.gif.identifier: "gif"][type],
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ChatMediaError.invalid }
        let count = CGImageSourceGetCount(source)
        guard (1...600).contains(count), (1...4096).contains(width), (1...4096).contains(height) else { throw ChatMediaError.invalid }
        var duration = 0.0
        for index in 0..<count {
            guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete,
                  let p = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let frameWidth = p[kCGImagePropertyPixelWidth] as? Int,
                  let frameHeight = p[kCGImagePropertyPixelHeight] as? Int,
                  (1...4096).contains(frameWidth), (1...4096).contains(frameHeight) else { throw ChatMediaError.invalid }
            if count > 1 {
                let gif = p[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
                duration += max(0.02, (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                    ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1)
            }
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1
        let swapsAxes = [5, 6, 7, 8].contains(orientation)
        let asset = Self(sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                         fileExtension: ext, width: swapsAxes ? height : width, height: swapsAxes ? width : height,
                         frameCount: count, duration: duration, byteCount: data.count)
        try asset.validate()
        return asset
    }
}

struct CharacterSticker: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let characterID: String
    var name: String
    var meaning: String
    let asset: ChatMediaAsset
    func validate() throws {
        try asset.validate()
        guard !characterID.isEmpty, characterID.count <= 120,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
              meaning.count <= 300 else { throw ChatMediaError.invalid }
    }
}

struct ChatAttachment: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case image, sticker }
    let id: UUID
    let kind: Kind
    let asset: ChatMediaAsset
    var sticker: CharacterSticker? = nil
    var description: String { kind == .image ? "[图片]" : "[表情：\(sticker?.name ?? "表情")] \(sticker?.meaning ?? "")" }
    func validate() throws {
        try asset.validate()
        if kind == .sticker {
            guard let sticker, sticker.asset == asset else { throw ChatMediaError.invalid }
            try sticker.validate()
        } else if sticker != nil { throw ChatMediaError.invalid }
    }
}

struct ChatMediaFiles: Sendable {
    let directory: URL
    private let resourcesURL: URL?
    init(historyURL: URL, resourcesURL: URL? = Bundle.main.resourceURL) {
        directory = historyURL.deletingLastPathComponent().appendingPathComponent("Media", isDirectory: true)
        self.resourcesURL = resourcesURL
    }
    func localURL(for asset: ChatMediaAsset) -> URL { directory.appendingPathComponent(asset.filename) }
    func url(for asset: ChatMediaAsset) -> URL {
        let local = localURL(for: asset)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        // Built-in files stay in the read-only App bundle. Only actually used
        // sticker snapshots enter media backups; importing the pack uses no disk copies.
        if let resourcesURL {
            for folder in [resourcesURL, resourcesURL.appendingPathComponent("BuiltinStickers", isDirectory: true)] {
                let bundled = folder.appendingPathComponent(asset.filename)
                if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
            }
        }
        return local
    }
    func data(for asset: ChatMediaAsset) throws -> Data {
        try asset.validate()
        let url = url(for: asset)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
              size.isSymbolicLink != true, size.fileSize == asset.byteCount else { throw ChatMediaError.missing }
        let data = try Data(contentsOf: url)
        guard try ChatMediaAsset.inspect(data) == asset else { throw ChatMediaError.missing }
        return data
    }
    @discardableResult func store(_ data: Data) throws -> ChatMediaAsset {
        let asset = try ChatMediaAsset.inspect(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Read lookup may resolve into the signed, read-only bundle. Writes and
        // metadata updates must ALWAYS target the writable user media directory.
        let destination = localURL(for: asset)
        try data.write(to: destination, options: .atomic)
        for item in [directory, destination] {
            var url = item; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            #endif
        }
        return asset
    }
    /// Send a bounded still preview to vision. Original GIF remains unchanged on disk.
    func visionURL(for asset: ChatMediaAsset) throws -> String {
        let bytes = try data(for: asset)
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1280] as CFDictionary) else { throw ChatMediaError.invalid }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw ChatMediaError.invalid }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ChatMediaError.invalid }
        return "data:image/jpeg;base64," + (output as Data).base64EncodedString()
    }
    /// Photos may supply HEIC or a 48 MP still. Convert only incompatible stills;
    /// GIF is always validated and preserved, never flattened as a fallback.
    static func compatiblePhoto(_ data: Data) throws -> Data {
        guard data.count <= 50 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete else { throw ChatMediaError.invalid }
        if CGImageSourceGetType(source) as String? == UTType.gif.identifier {
            _ = try ChatMediaAsset.inspect(data); return data
        }
        if (try? ChatMediaAsset.inspect(data)) != nil { return data }
        guard CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else { throw ChatMediaError.invalid }
        let output = NSMutableData()
        let hasAlpha = [CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo)
        let type = hasAlpha ? UTType.png : .jpeg
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { throw ChatMediaError.invalid }
        CGImageDestinationAddImage(destination, image, hasAlpha ? nil : [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ChatMediaError.invalid }
        _ = try ChatMediaAsset.inspect(output as Data)
        return output as Data
    }
}

extension ChatHistory {
    var mediaAssets: [ChatMediaAsset] {
        var all = (stickers ?? []).map(\.asset)
        for chat in conversations {
            all.append(contentsOf: (chat.draftAttachments ?? []).map(\.asset))
            for message in chat.messages {
                all.append(contentsOf: (message.attachments ?? []).map(\.asset))
                all.append(contentsOf: (message.toolReceipts ?? []).compactMap { $0.sticker?.asset })
            }
        }
        return Array(Set(all)).sorted { $0.filename < $1.filename }
    }
}
