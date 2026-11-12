import Foundation

enum JiraError: Error, Equatable {
    case notConfigured
    case invalidSite
    case unauthorized
    case http(Int)
    case network(String)

    var userMessage: String {
        switch self {
        case .notConfigured: return "Add your Jira site, email and token in Settings"
        case .invalidSite: return "Jira site must be a host like example.atlassian.net"
        case .unauthorized: return "Jira rejected the token — update it in Settings"
        case .http(let code): return "Jira returned HTTP \(code)"
        case .network(let text): return text
        }
    }
}

protocol JiraFetching {
    func fetchInProgress() async throws -> [JiraIssue]
    func fetchReadyToRelease() async throws -> [JiraIssue]
    func fetchMentions() async throws -> MentionFeed
}

actor JiraClient: JiraFetching {
    private static let issueFields = ["summary", "status", "updated"]
    private static let maxMentions = 20
    private static let maxCandidates = 15

    private let config: AppConfig
    private let token: String?
    private let transport: HTTPTransport
    private let now: () -> Date
    private var accountId: String?

    init(config: AppConfig, token: String?, transport: HTTPTransport, now: @escaping () -> Date) {
        self.config = config
        self.token = token
        self.transport = transport
        self.now = now
    }

    func fetchInProgress() async throws -> [JiraIssue] {
        let connection = try makeConnection()
        let data = try await connection.search(jql: JiraParsing.inProgressJQL(statuses: config.inProgressStatuses), maxResults: 50)
        return try JiraParsing.parseIssues(data, site: connection.site)
    }

    func fetchReadyToRelease() async throws -> [JiraIssue] {
        let connection = try makeConnection()
        let data = try await connection.search(jql: JiraParsing.releaseJQL(statuses: config.releaseStatuses), maxResults: 50)
        return try JiraParsing.parseIssues(data, site: connection.site)
    }

    func fetchMentions() async throws -> MentionFeed {
        let connection = try makeConnection()
        let me = try await resolveAccountId(connection)
        let since = now().addingTimeInterval(-TimeInterval(config.mentionsLookbackDays) * 86_400)
        let data = try await connection.search(jql: JiraParsing.mentionCandidatesJQL(lookbackDays: config.mentionsLookbackDays), maxResults: Self.maxCandidates)
        let issues = try JiraParsing.parseIssues(data, site: connection.site)
        let results = await withTaskGroup(of: Result<[Mention], Error>.self) { group in
            for issue in issues {
                group.addTask {
                    do {
                        let comments = try await connection.comments(issueKey: issue.key)
                        return .success(try JiraParsing.parseMentions(comments, issue: issue, accountId: me, since: since, site: connection.site))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<[Mention], Error>] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        var merged: [Mention] = []
        var firstError: Error?
        for result in results {
            switch result {
            case .success(let mentions): merged.append(contentsOf: mentions)
            case .failure(let error): firstError = firstError ?? error
            }
        }
        if let firstError, results.allSatisfy({ if case .failure = $0 { return true } else { return false } }) {
            throw firstError
        }
        let sorted = merged.sorted { $0.createdAt > $1.createdAt }
        let isComplete = firstError == nil && issues.count < Self.maxCandidates && sorted.count <= Self.maxMentions
        return MentionFeed(mentions: Array(sorted.prefix(Self.maxMentions)), isComplete: isComplete)
    }

    private func resolveAccountId(_ connection: Connection) async throws -> String {
        if let accountId {
            return accountId
        }
        let resolved = try JiraParsing.parseAccountId(try await connection.get(path: "/rest/api/3/myself", query: []))
        accountId = resolved
        return resolved
    }

    private func makeConnection() throws -> Connection {
        guard let token, !token.isEmpty, !config.jiraEmail.isEmpty else {
            throw JiraError.notConfigured
        }
        let site = config.jiraSite.trimmingCharacters(in: .whitespaces)
        guard !site.isEmpty else {
            throw JiraError.notConfigured
        }
        guard site.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else {
            throw JiraError.invalidSite
        }
        let credentials = Data("\(config.jiraEmail):\(token)".utf8).base64EncodedString()
        return Connection(site: site, authorization: "Basic \(credentials)", transport: transport)
    }

    private struct Connection {
        let site: String
        let authorization: String
        let transport: HTTPTransport

        func search(jql: String, maxResults: Int) async throws -> Data {
            let body: [String: Any] = ["jql": jql, "fields": JiraClient.issueFields, "maxResults": maxResults]
            var request = try makeRequest(path: "/rest/api/3/search/jql", query: [])
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return try await send(request)
        }

        func comments(issueKey: String) async throws -> Data {
            try await get(
                path: "/rest/api/3/issue/\(issueKey)/comment",
                query: [URLQueryItem(name: "orderBy", value: "-created"), URLQueryItem(name: "maxResults", value: "30")]
            )
        }

        func get(path: String, query: [URLQueryItem]) async throws -> Data {
            var request = try makeRequest(path: path, query: query)
            request.httpMethod = "GET"
            return try await send(request)
        }

        private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
            var components = URLComponents()
            components.scheme = "https"
            components.host = site
            components.path = path
            if !query.isEmpty {
                components.queryItems = query
            }
            guard let url = components.url else {
                throw JiraError.invalidSite
            }
            var request = URLRequest(url: url)
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }

        private func send(_ request: URLRequest) async throws -> Data {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch {
                throw JiraError.network(error.localizedDescription)
            }
            switch response.statusCode {
            case 200..<300: return data
            case 401, 403: throw JiraError.unauthorized
            default: throw JiraError.http(response.statusCode)
            }
        }
    }
}
