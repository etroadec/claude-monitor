import Foundation

struct StatusIncident {
    let title: String
    let date: Date
    let link: String
    let description: String
    let isRecent: Bool // less than 24h old
}

class StatusFeedClient {
    private let feedURL = "https://status.claude.com/history.atom"

    func fetchIncidents(completion: @escaping (Result<[StatusIncident], Error>) -> Void) {
        guard let url = URL(string: feedURL) else {
            completion(.failure(StatusError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(StatusError.noData))
                return
            }

            let parser = AtomParser(data: data)
            let incidents = parser.parse()
            completion(.success(incidents))
        }.resume()
    }
}

// Simple Atom XML parser
class AtomParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var incidents: [StatusIncident] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentUpdated = ""
    private var currentContent = ""
    private var inEntry = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> [StatusIncident] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return incidents
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "entry" {
            inEntry = true
            currentTitle = ""
            currentLink = ""
            currentUpdated = ""
            currentContent = ""
        }
        if elementName == "link" && inEntry {
            currentLink = attributes["href"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "updated": currentUpdated += string
        case "content": currentContent += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "entry" {
            inEntry = false
            let date = parseDate(currentUpdated) ?? Date.distantPast
            let now = Date()
            let isRecent = now.timeIntervalSince(date) < 86400 // 24h

            // Strip HTML tags for display
            let cleanDesc = currentContent
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let incident = StatusIncident(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                link: currentLink,
                description: String(cleanDesc.prefix(200)),
                isRecent: isRecent
            )
            incidents.append(incident)
        }
        currentElement = ""
    }

    private func parseDate(_ str: String) -> Date? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: trimmed) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}

enum StatusError: LocalizedError {
    case invalidURL, noData
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL invalide"
        case .noData: return "Pas de données"
        }
    }
}
