import Cocoa
import CommonCrypto

class OAuthClient {
    static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    static let scopes = "user:inference user:profile"

    private var codeVerifier: String?
    private var state: String?
    private var redirectURI: String?
    private var server: LocalHTTPServer?
    private var completion: ((Result<OAuthTokens, Error>) -> Void)?

    struct OAuthTokens {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
    }

    func authorize(completion: @escaping (Result<OAuthTokens, Error>) -> Void) {
        self.completion = completion

        codeVerifier = generateRandomString()
        state = generateRandomString()
        let codeChallenge = generateCodeChallenge(from: codeVerifier!)

        server = LocalHTTPServer()
        guard let port = server?.start(handler: { [weak self] code, returnedState in
            debugLog("[OAuth] Callback: code=\(code?.prefix(10) ?? "nil")")
            self?.handleCallback(code: code, state: returnedState)
        }) else {
            debugLog("[OAuth] Failed to start server")
            completion(.failure(OAuthError.serverFailed))
            return
        }

        redirectURI = "http://localhost:\(port)/callback"
        debugLog("[OAuth] Server on port \(port)")

        var components = URLComponents(string: OAuthClient.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: OAuthClient.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: OAuthClient.scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        NSWorkspace.shared.open(components.url!)
    }

    func cancel() {
        server?.stop()
        server = nil
        completion = nil
    }

    private func handleCallback(code: String?, state returnedState: String?) {
        server?.stop()
        server = nil

        guard let code = code else {
            completion?(.failure(OAuthError.noCode))
            return
        }
        guard returnedState == self.state else {
            completion?(.failure(OAuthError.stateMismatch))
            return
        }
        exchangeCode(code)
    }

    private func exchangeCode(_ code: String) {
        debugLog("[OAuth] Exchanging code...")
        guard let url = URL(string: OAuthClient.tokenURL) else {
            completion?(.failure(OAuthError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI!,
            "client_id": OAuthClient.clientId,
            "code_verifier": codeVerifier!,
            "state": state!,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                debugLog("[OAuth] Network error: \(error)")
                self?.completion?(.failure(error))
                return
            }

            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            debugLog("[OAuth] Token response: \(httpStatus)")

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self?.completion?(.failure(OAuthError.invalidResponse))
                return
            }

            if let err = json["error"] as? String {
                self?.completion?(.failure(OAuthError.serverError(json["error_description"] as? String ?? err)))
                return
            }

            guard let accessToken = json["access_token"] as? String else {
                self?.completion?(.failure(OAuthError.noToken))
                return
            }

            debugLog("[OAuth] Token obtained")
            let tokens = OAuthTokens(
                accessToken: accessToken,
                refreshToken: json["refresh_token"] as? String,
                expiresIn: json["expires_in"] as? Int
            )
            self?.completion?(.success(tokens))
        }.resume()
    }

    // MARK: - Token Refresh

    static func refreshAccessToken(_ refreshToken: String, completion: @escaping (Result<OAuthTokens, Error>) -> Void) {
        guard let url = URL(string: tokenURL) else {
            completion(.failure(OAuthError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        debugLog("[OAuth] Refreshing token...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            debugLog("[OAuth] Refresh response: \(httpStatus)")

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                completion(.failure(OAuthError.invalidResponse))
                return
            }

            let tokens = OAuthTokens(
                accessToken: accessToken,
                refreshToken: json["refresh_token"] as? String,
                expiresIn: json["expires_in"] as? Int
            )
            completion(.success(tokens))
        }.resume()
    }

    // MARK: - PKCE

    private func generateRandomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthError: LocalizedError {
    case serverFailed, noCode, stateMismatch, invalidURL, invalidResponse, noToken
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverFailed: return "Serveur local indisponible"
        case .noCode: return "Pas de code reçu"
        case .stateMismatch: return "Erreur de sécurité"
        case .invalidURL: return "URL invalide"
        case .invalidResponse: return "Réponse invalide"
        case .noToken: return "Pas de token reçu"
        case .serverError(let msg): return msg
        }
    }
}
