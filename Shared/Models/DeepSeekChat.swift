import Foundation

protocol AISecretSource: Sendable {
    func readKey() throws -> String?
}

struct MissingAISecret: AISecretSource {
    func readKey() throws -> String? { nil }
}

struct DeepSeekModel: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String?
    var title: String { name ?? id }
    static let defaults = [Self(id: "deepseek-flash", name: "DeepSeek Flash"), Self(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro")]
}

/// AsyncBytes.lines can omit empty lines. SSE needs those lines as event boundaries.
struct SSELines {
    private var buffer: [UInt8] = []
    private var previousCR = false
    mutating func byte(_ value: UInt8) throws -> String? {
        if previousCR {
            previousCR = false
            if value == 10 { return nil }
        }
        if value == 10 || value == 13 {
            previousCR = value == 13
            guard let line = String(bytes: buffer, encoding: .utf8) else { throw AIChatError.invalidResponse }
            buffer.removeAll(keepingCapacity: true)
            return line
        }
        guard buffer.count < 1_048_576 else { throw AIChatError.invalidResponse }
        buffer.append(value)
        return nil
    }
    mutating func finish() throws -> String? {
        guard !buffer.isEmpty else { return nil }
        guard let line = String(bytes: buffer, encoding: .utf8) else { throw AIChatError.invalidResponse }
        buffer.removeAll(keepingCapacity: true)
        return line
    }
}

/// Only the public answer is accumulated; reasoning_content never enters history or backups.
struct DeepSeekStream {
    private var eventLines: [String] = []
    private(set) var text = ""
    private(set) var done = false
    private(set) var finishReason: String?
    var collectTools = false
    private(set) var reasoning = ""
    private var toolFragments: [Int: ChatToolCall] = [:]
    var toolCalls: [ChatToolCall] { toolFragments.keys.sorted().compactMap { toolFragments[$0] } }

    mutating func line(_ line: String) throws {
        guard !done else { return }
        guard line.utf8.count <= 1_048_576 else { throw AIChatError.invalidResponse }
        if line.isEmpty { try flush(); return }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            eventLines.append(value)
            guard eventLines.reduce(0, { $0 + $1.utf8.count }) <= 1_048_576 else { throw AIChatError.invalidResponse }
        }
    }

    mutating func flush() throws {
        guard !eventLines.isEmpty else { return }
        let payload = eventLines.joined(separator: "\n")
        eventLines = []
        if payload == "[DONE]" { done = true; return }
        guard !payload.isEmpty else { return }
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable {
                    struct Tool: Decodable {
                        struct Function: Decodable { var name: String?; var arguments: String? }
                        let index: Int; var id: String?; var type: String?; var function: Function?
                    }
                    var content: String?; var reasoning_content: String?; var tool_calls: [Tool]?
                }
                var delta: Delta?
                var finish_reason: String?
            }
            var choices: [Choice]?
            var error: ServiceError?
            struct ServiceError: Decodable { var message: String? }
        }
        let chunk: Chunk
        do { chunk = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)) }
        catch { throw AIChatError.invalidResponse }
        guard chunk.error == nil else { throw AIChatError.interrupted }
        if let choice = chunk.choices?.first {
            if let content = choice.delta?.content { text += content }
            if collectTools {
                reasoning += choice.delta?.reasoning_content ?? ""
                for fragment in choice.delta?.tool_calls ?? [] {
                    guard (0..<8).contains(fragment.index), fragment.type == nil || fragment.type == "function" else { throw AIChatError.invalidResponse }
                    var call = toolFragments[fragment.index] ?? ChatToolCall(id: "", function: .init(name: "", arguments: ""))
                    call.id += fragment.id ?? ""
                    call.function.name += fragment.function?.name ?? ""
                    call.function.arguments += fragment.function?.arguments ?? ""
                    guard call.id.count <= 200, call.function.name.count <= 100, call.function.arguments.utf8.count <= 8192 else { throw AIChatError.invalidResponse }
                    toolFragments[fragment.index] = call
                }
                guard reasoning.utf8.count <= 1_048_576 else { throw AIChatError.invalidResponse }
            }
            if let reason = choice.finish_reason { finishReason = reason }
        }
        guard text.utf8.count <= 1_048_576 else { throw AIChatError.invalidResponse }
    }

    mutating func finish() throws -> String {
        try flush()
        if collectTools, finishReason == "tool_calls" {
            guard done, !toolCalls.isEmpty, Set(toolCalls.map(\.id)).count == toolCalls.count else { throw AIChatError.interrupted }
            for call in toolCalls { _ = try call.arguments() }
            return text
        }
        guard toolCalls.isEmpty else { throw AIChatError.invalidResponse }
        if finishReason == "length" { throw AIChatError.truncated }
        guard done, finishReason == "stop" else { throw AIChatError.interrupted }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatError.emptyReply }
        return text
    }
}

private final class NoChatRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct DeepSeekChatClient: @unchecked Sendable {
    static let baseURL = URL(string: "https://api.deepseek.com")!
    let session: URLSession

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 300
            config.urlCache = nil
            config.httpCookieStorage = nil
            self.session = URLSession(configuration: config, delegate: NoChatRedirects(), delegateQueue: nil)
        }
    }

    static func validateKey(_ key: String) throws {
        guard !key.isEmpty else { throw AIChatError.missingKey }
        guard key.count <= 512, key.hasPrefix("sk-"), key.utf8.allSatisfy({ (33...126).contains($0) }) else { throw AIChatError.invalidKey }
    }

    static func request(key: String, chat: ChatReplyRequest? = nil, messages: [AIChatMessage]? = nil, includeTools: Bool = false) throws -> URLRequest {
        try validateKey(key)
        var request = URLRequest(url: baseURL.appendingPathComponent(chat == nil ? "models" : "chat/completions"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let chat {
            let profile = chat.profile ?? .standard(for: chat.character)
            try profile.validate()
            struct Body: Encodable {
                struct Thinking: Encodable { let type: String }
                let model: String
                let messages: [AIChatMessage]
                let stream = true
                let max_tokens: Int
                let thinking: Thinking
            }
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(Body(model: profile.model, messages: try messages ?? AIChatContext.messages(for: chat),
                max_tokens: profile.maxOutputTokens, thinking: .init(type: profile.thinking ? "enabled" : "disabled")))
            if includeTools, !ChatTools.allowed(for: chat).isEmpty {
                var object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                object["tools"] = ChatTools.allowed(for: chat).map(\.schema)
                request.httpBody = try JSONSerialization.data(withJSONObject: object)
            }
        }
        return request
    }

    private func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw AIChatError.invalidResponse }
        guard response.statusCode == 200 else { throw AIChatError.http(response.statusCode) }
    }

    static func safeError(_ error: Error) -> Error {
        if error is AIChatError || error is ChatError || error is CancellationError { return error }
        if let url = error as? URLError {
            if url.code == .cancelled { return CancellationError() }
            if url.code == .timedOut { return AIChatError.timeout }
        }
        return AIChatError.network
    }

    func models(key: String) async throws -> [DeepSeekModel] {
        do {
            let (data, response) = try await session.data(for: Self.request(key: key))
            try check(response)
            guard data.count <= 1_048_576 else { throw AIChatError.invalidResponse }
            struct List: Decodable { let data: [DeepSeekModel] }
            guard let list = try? JSONDecoder().decode(List.self, from: data), !list.data.isEmpty,
                  Set(list.data.map(\.id)).count == list.data.count,
                  list.data.allSatisfy({ model in var p = AICharacterProfile(); p.model = model.id; return (try? p.validate()) != nil }) else { throw AIChatError.invalidResponse }
            return list.data.sorted { $0.id < $1.id }
        } catch { throw Self.safeError(error) }
    }

    func reply(key: String, request: ChatReplyRequest, onPartial: @escaping @Sendable (String) async -> Void,
               onTool: ChatToolHandler? = nil) async throws -> String {
        do {
            var messages = try AIChatContext.messages(for: request)
            let tools = onTool == nil ? [] : ChatTools.allowed(for: request)
            var prefix = ""
            var callCount = 0
            for _ in 0..<6 {
                try Task.checkCancellation()
                let (bytes, response) = try await session.bytes(for: Self.request(key: key, chat: request, messages: messages, includeTools: !tools.isEmpty))
                try check(response)
                guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw AIChatError.invalidResponse }
                var stream = DeepSeekStream(); stream.collectTools = !tools.isEmpty
                var lines = SSELines()
                var lastPublished = ""; var lastTime = Date.distantPast
                do {
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let line = try lines.byte(byte) else { continue }
                        try stream.line(line)
                        if stream.text != lastPublished, Date().timeIntervalSince(lastTime) >= 0.06 {
                            await onPartial(prefix + stream.text); lastPublished = stream.text; lastTime = .now
                        }
                        if stream.done { break }
                    }
                    if let tail = try lines.finish() { try stream.line(tail) }
                    let answer = try stream.finish()
                    if stream.toolCalls.isEmpty {
                        await onPartial(prefix + answer)
                        return prefix + answer
                    }
                    callCount += stream.toolCalls.count
                    guard callCount <= 8, let onTool else { throw AIChatError.invalidResponse }
                    guard stream.toolCalls.allSatisfy({ call in tools.contains { $0.name == call.function.name } }) else { throw AIChatError.invalidResponse }
                    messages.append(.init(role: "assistant", content: answer, tool_calls: stream.toolCalls,
                        reasoning_content: request.profile?.thinking == true ? stream.reasoning : nil))
                    for call in stream.toolCalls {
                        try Task.checkCancellation()
                        let result = try await onTool(call)
                        guard result.count <= 6000 else { throw AIChatError.invalidResponse }
                        messages.append(.init(role: "tool", content: result, tool_call_id: call.id))
                    }
                    prefix += answer.isEmpty ? "" : answer + "\n"
                } catch {
                    if stream.text != lastPublished { await onPartial(prefix + stream.text) }
                    throw error
                }
            }
            throw AIChatError.interrupted
        } catch { throw Self.safeError(error) }
    }

}

struct DeepSeekChatReplyProvider: ChatReplyProvider {
    let secrets: any AISecretSource
    var client = DeepSeekChatClient()
    func reply(to request: ChatReplyRequest) async throws -> String {
        try await reply(to: request, onPartial: { _ in })
    }
    func reply(to request: ChatReplyRequest, onPartial: @escaping @Sendable (String) async -> Void, onTool: @escaping ChatToolHandler) async throws -> String {
        guard let key = try secrets.readKey() else { throw AIChatError.missingKey }
        return try await client.reply(key: key, request: request, onPartial: onPartial, onTool: onTool)
    }
    func reply(to request: ChatReplyRequest, onPartial: @escaping @Sendable (String) async -> Void) async throws -> String {
        guard let key = try secrets.readKey() else { throw AIChatError.missingKey }
        return try await client.reply(key: key, request: request, onPartial: onPartial)
    }
}
