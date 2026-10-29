import Foundation
import Security

/// App-only, device-local credential. No synchronizable item or shared signing access group.
struct AIChatCredentials: AISecretSource {
    private var service: String {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--chat-test-store"), args.indices.contains(index + 1),
           UUID(uuidString: args[index + 1]) != nil { return "com.maiverse.deepseek.test.\(args[index + 1])" }
        #endif
        return "com.maiverse.deepseek"
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key", kSecAttrSynchronizable as String: false]
    }
    func readKey() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw CredentialError.unavailable }
        return key
    }
    func save(_ key: String) throws {
        try DeepSeekChatClient.validateKey(key)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(attributes) { _, new in new }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw CredentialError.unavailable }
        } else if status != errSecSuccess { throw CredentialError.unavailable }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.unavailable }
    }
    enum CredentialError: LocalizedError {
        case unavailable
        var errorDescription: String? { "无法访问钥匙串，请解锁手机后重试。" }
    }
}
