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
        guard status == errSecSuccess else { throw CredentialError.system(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw CredentialError.unavailable }
        return key
    }
    func save(_ key: String) throws {
        try DeepSeekChatClient.validateKey(key)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(attributes) { _, new in new }
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialError.system(added) }
        } else if status != errSecSuccess { throw CredentialError.system(status) }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.system(status) }
    }
    enum CredentialError: LocalizedError {
        case unavailable
        case system(OSStatus)
        var errorDescription: String? {
            switch self {
            case .system(errSecMissingEntitlement): return "当前安装包没有有效的钥匙串访问身份，请检查 App 签名。"
            case .system(errSecInteractionNotAllowed): return "无法访问钥匙串，请解锁手机后重试。"
            default: return "钥匙串暂不可用，请稍后重试。"
            }
        }
    }
}
