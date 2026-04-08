import Foundation

class Config {
    static let shared = Config()

    private let configDir: URL
    private let configFile: URL

    var accessToken: String = ""
    var refreshToken: String = ""
    var refreshInterval: TimeInterval = 300 // 5 minutes
    var isConnected: Bool { !accessToken.isEmpty }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configDir = appSupport.appendingPathComponent("ClaudeMonitor")
        configFile = configDir.appendingPathComponent("config.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: configFile.path) else { return }
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let token = json["accessToken"] as? String { accessToken = token }
        if let token = json["refreshToken"] as? String { refreshToken = token }
        if let interval = json["refreshInterval"] as? TimeInterval { refreshInterval = interval }
    }

    func save() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "accessToken": accessToken,
            "refreshToken": refreshToken,
            "refreshInterval": refreshInterval,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: configFile)
        }
    }

    func saveTokens(_ tokens: OAuthClient.OAuthTokens) {
        accessToken = tokens.accessToken
        if let rt = tokens.refreshToken { refreshToken = rt }
        save()
    }

    func disconnect() {
        accessToken = ""
        refreshToken = ""
        save()
    }
}
