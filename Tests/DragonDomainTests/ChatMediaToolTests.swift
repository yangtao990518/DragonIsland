import XCTest
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import DragonDomain

final class ChatMediaToolTests: XCTestCase {
    static func image(gif: Bool = false) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, (gif ? UTType.gif : .png).identifier as CFString, gif ? 2 : 1, nil))
        for index in 0..<(gif ? 2 : 1) {
            let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: index == 0 ? 1 : 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let image = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, image, gif ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary : nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    private func history(attachment: ChatAttachment? = nil) throws -> ChatHistory {
        var value = ChatHistory()
        let id = try value.create(kind: .direct, name: "", characterIDs: ["xiaobai"], availableIDs: ["xiaobai"])
        _ = try value.enqueue(attachment == nil ? "你好" : "", in: id, availableIDs: ["xiaobai"], attachments: attachment.map { [$0] } ?? [])
        return value
    }
    func testStaticAndGIFDetectedFromBytesAndKeptLosslessly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ChatMediaFiles(historyURL: root.appendingPathComponent("history.json"))
        for gif in [false, true] {
            let bytes = try Self.image(gif: gif)
            let asset = try files.store(bytes)
            XCTAssertEqual(asset.animated, gif)
            XCTAssertEqual(asset.frameCount, gif ? 2 : 1)
            XCTAssertEqual(try files.data(for: asset), bytes)
            XCTAssertTrue(try files.visionURL(for: asset).hasPrefix("data:image/jpeg;base64,"))
        }
        XCTAssertThrowsError(try ChatMediaAsset.inspect(Data("not an image".utf8)))
    }
    func testImageOnlyMessageAndLegacyJSONRoundTrip() throws {
        let item = ChatAttachment(id: UUID(), kind: .image, asset: try .inspect(Self.image()))
        let value = try history(attachment: item)
        try value.validate()
        XCTAssertEqual(value.conversations[0].messages[0].text, "")
        XCTAssertEqual(try JSONDecoder().decode(ChatHistory.self, from: JSONEncoder().encode(value)), value)
        let legacy = try history()
        XCTAssertNil(try JSONDecoder().decode(ChatHistory.self, from: JSONEncoder().encode(legacy)).stickers)
    }
    func testBackupIncludesOriginalsAndRejectsMissingOrTamperedMedia() throws {
        let bytes = try Self.image(gif: true)
        let asset = try ChatMediaAsset.inspect(bytes)
        let value = try history(attachment: .init(id: UUID(), kind: .image, asset: asset))
        let good = try ChatBackup(history: value, media: [asset.filename: bytes])
        XCTAssertEqual(try ChatBackup.decode(JSONEncoder().encode(good)).history, value)
        XCTAssertThrowsError(try ChatBackup.decode(JSONEncoder().encode(ChatBackup(history: value, media: [:]))))
        var bad = good; bad.media = [asset.filename: Data([1, 2, 3])]
        XCTAssertThrowsError(try ChatBackup.decode(JSONEncoder().encode(bad)))
        XCTAssertEqual(try ChatBackup.decode(JSONEncoder().encode(ChatBackup(history: history()))).version, 1)
    }
    func testCrossCharacterStickerInReplyAndUnsafePathsRejected() throws {
        let asset = try ChatMediaAsset.inspect(Self.image())
        let sticker = CharacterSticker(id: UUID(), characterID: "dafeiyu", name: "开心", meaning: "高兴", asset: asset)
        var value = try history()
        var reply = ChatMessage.reply("", character: .xiaobai, to: value.conversations[0].messages[0].id)
        reply.attachments = [.init(id: UUID(), kind: .sticker, asset: asset, sticker: sticker)]
        value.conversations[0].messages.append(reply)
        XCTAssertThrowsError(try value.validate())
        let unsafe = ChatMediaAsset(sha256: "../secret", fileExtension: "png", width: 1, height: 1, frameCount: 1, duration: 0, byteCount: 1)
        XCTAssertThrowsError(try unsafe.validate())
    }
    func testToolArgumentsStrictAndFingerprintIndependentOfArgumentOrder() throws {
        let a = ChatToolCall(id: "1", function: .init(name: "create_alarm", arguments: #"{"title":"见面","date":"2026-12-01T12:00:00+08:00"}"#))
        let b = ChatToolCall(id: "2", function: .init(name: "create_alarm", arguments: #"{"date":"2026-12-01T12:00:00+08:00","title":"见面"}"#))
        XCTAssertEqual(try a.fingerprint(characterID: "xiaobai"), try b.fingerprint(characterID: "xiaobai"))
        XCTAssertNotEqual(try a.fingerprint(characterID: "xiaobai"), try b.fingerprint(characterID: "dafeiyu"))
        XCTAssertThrowsError(try ChatToolCall(id: "3", function: .init(name: "app_state", arguments: #"{"extra":"x"}"#)).arguments())
        XCTAssertThrowsError(try ChatToolCall(id: "4", function: .init(name: "shell", arguments: "{}")).arguments())
    }
    func testFragmentedToolStreamCannotExecuteTruncatedCalls() throws {
        var stream = DeepSeekStream(); stream.collectTools = true
        for event in [
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"app_","arguments":"{"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"state","arguments":"}"}}]},"finish_reason":"tool_calls"}]}"#
        ] { try stream.line("data: " + event); try stream.line("") }
        var truncated = stream
        XCTAssertThrowsError(try truncated.finish())
        try stream.line("data: [DONE]"); try stream.line("")
        XCTAssertEqual(try stream.finish(), "")
        XCTAssertEqual(stream.toolCalls.first?.function.name, "app_state")
        XCTAssertEqual(try stream.toolCalls.first?.arguments(), [:])
    }
    func testVisionPayloadAndToolPermissionsAreExplicit() throws {
        let user = ChatMessage.user("看看", recipients: ["xiaobai"])
        var request = ChatReplyRequest(conversationID: UUID(), kind: .direct, groupName: "", members: [.xiaobai], character: .xiaobai, userMessage: user, history: [user], profile: AICharacterProfile())
        request.imageURLs[user.id] = ["data:image/jpeg;base64,eA=="]
        let body = try JSONSerialization.jsonObject(with: DeepSeekChatClient.request(key: "sk-test", chat: request, includeTools: true).httpBody!) as! [String: Any]
        XCTAssertNil(body["tools"])
        let messages = body["messages"] as! [[String: Any]]
        XCTAssertEqual((messages.last?["content"] as? [[String: Any]])?.last?["type"] as? String, "image_url")
        request.profile?.appControl = true
        let enabled = try JSONSerialization.jsonObject(with: DeepSeekChatClient.request(key: "sk-test", chat: request, includeTools: true).httpBody!) as! [String: Any]
        XCTAssertEqual((enabled["tools"] as? [Any])?.count, ChatTools.all.count - 1)
    }
}
