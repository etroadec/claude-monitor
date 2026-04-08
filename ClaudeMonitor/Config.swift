import Foundation
import Security

class Config {
    static let shared = Config()

    private static let serviceName = "com.edgard.claude-monitor"
    private static let accessTokenKey = "accessToken"
    private static let refreshTokenKey = "refreshToken"
    private static let expiresAtKey = "expiresAt"

    var accessToken: String = ""
    var refreshToken: String = ""
    var expiresAt: Date?
    var isConnected: Bool { !accessToken.isEmpty }

    /// True if the token will expire within 5 minutes
    var isTokenExpiringSoon: Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 300
    }

    private init() {
        load()
    }

    func load() {
        accessToken = readKeychain(key: Config.accessTokenKey) ?? ""
        refreshToken = readKeychain(key: Config.refreshTokenKey) ?? ""
        if let expiresStr = readKeychain(key: Config.expiresAtKey),
           let interval = Double(expiresStr) {
            expiresAt = Date(timeIntervalSince1970: interval)
        }
    }

    func save() {
        writeKeychain(key: Config.accessTokenKey, value: accessToken)
        writeKeychain(key: Config.refreshTokenKey, value: refreshToken)
        if let expiresAt = expiresAt {
            writeKeychain(key: Config.expiresAtKey, value: String(expiresAt.timeIntervalSince1970))
        }
    }

    func saveTokens(_ tokens: OAuthClient.OAuthTokens) {
        accessToken = tokens.accessToken
        if let rt = tokens.refreshToken { refreshToken = rt }
        if let expiresIn = tokens.expiresIn {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
        save()
    }

    func disconnect() {
        accessToken = ""
        refreshToken = ""
        expiresAt = nil
        deleteKeychain(key: Config.accessTokenKey)
        deleteKeychain(key: Config.refreshTokenKey)
        deleteKeychain(key: Config.expiresAtKey)
        // Clean up legacy plaintext config
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacyFile = appSupport.appendingPathComponent("ClaudeMonitor/config.json")
        try? FileManager.default.removeItem(at: legacyFile)
    }

    // MARK: - Keychain helpers

    private func readKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        deleteKeychain(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
