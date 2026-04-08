import Foundation

struct UsageBucket {
    let utilization: Double
    let resetsAt: Date?
}

struct ExtraUsage {
    let isEnabled: Bool
    let monthlyLimit: Int
    let usedCredits: Double
    let utilization: Double
}

struct UsageInfo {
    let fiveHour: UsageBucket
    let sevenDay: UsageBucket
    let sevenDaySonnet: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let extraUsage: ExtraUsage?

    /// Most restrictive limit for the menu bar display
    var displayPercent: Double { max(fiveHour.utilization, sevenDay.utilization) }
    var displayReset: Date? { fiveHour.resetsAt }
}

class AnthropicAPIClient {
    private let usageURL = "https://api.anthropic.com/api/oauth/usage"

    func fetchUsage(token: String, completion: @escaping (Result<UsageInfo, Error>) -> Void) {
        guard let url = URL(string: usageURL) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        debugLog("[API] GET \(usageURL)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                debugLog("[API] Network error: \(error)")
                completion(.failure(error))
                return
            }

            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
            debugLog("[API] Response \(httpStatus): \(bodyStr.prefix(500))")

            if httpStatus == 401 || httpStatus == 403 {
                completion(.failure(APIError.unauthorized))
                return
            }
            if httpStatus == 429 {
                completion(.failure(APIError.rateLimited))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(APIError.invalidResponse))
                return
            }

            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                completion(.failure(APIError.serverError(msg)))
                return
            }

            let info = UsageInfo(
                fiveHour: self.parseBucket(json["five_hour"]),
                sevenDay: self.parseBucket(json["seven_day"]),
                sevenDaySonnet: self.parseBucketOptional(json["seven_day_sonnet"]),
                sevenDayOpus: self.parseBucketOptional(json["seven_day_opus"]),
                extraUsage: self.parseExtra(json["extra_usage"])
            )
            completion(.success(info))
        }.resume()
    }

    private func parseBucket(_ value: Any?) -> UsageBucket {
        guard let dict = value as? [String: Any] else {
            return UsageBucket(utilization: 0, resetsAt: nil)
        }
        return UsageBucket(
            utilization: dict["utilization"] as? Double ?? 0,
            resetsAt: parseDate(dict["resets_at"] as? String)
        )
    }

    private func parseBucketOptional(_ value: Any?) -> UsageBucket? {
        guard let dict = value as? [String: Any] else { return nil }
        return UsageBucket(
            utilization: dict["utilization"] as? Double ?? 0,
            resetsAt: parseDate(dict["resets_at"] as? String)
        )
    }

    private func parseExtra(_ value: Any?) -> ExtraUsage? {
        guard let dict = value as? [String: Any] else { return nil }
        return ExtraUsage(
            isEnabled: dict["is_enabled"] as? Bool ?? false,
            monthlyLimit: dict["monthly_limit"] as? Int ?? 0,
            usedCredits: dict["used_credits"] as? Double ?? 0,
            utilization: dict["utilization"] as? Double ?? 0
        )
    }

    private func parseDate(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }
}

enum APIError: LocalizedError {
    case invalidURL, invalidResponse, unauthorized, rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL invalide"
        case .invalidResponse: return "Réponse invalide"
        case .unauthorized: return "Token expiré — reconnectez-vous"
        case .rateLimited: return "Rate limité — réessai bientôt"
        case .serverError(let msg): return msg
        }
    }
}
