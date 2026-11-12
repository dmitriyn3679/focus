import Foundation

final class FakeTransport: HTTPTransport {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    var responses: [String: (Int, String)]
    var errors: [String: Error] = [:]

    init(responses: [String: (Int, String)] = [:]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let url = request.url!
        if let error = errors[url.path] {
            throw error
        }
        let (status, body) = responses[url.path] ?? (404, "{}")
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func requests(path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }
}

private let searchPath = "/rest/api/3/search/jql"
private let myselfPath = "/rest/api/3/myself"
private let fixedNow = utc(2026, 11, 9, 12)

private func jiraConfig(email: String = "me@example.com", site: String = "acme.atlassian.net") -> AppConfig {
    var config = AppConfig.default
    config.jiraEmail = email
    config.jiraSite = site
    return config
}

private func client(_ transport: FakeTransport, config: AppConfig = jiraConfig(), token: String? = "tok") -> JiraClient {
    JiraClient(config: config, token: token, transport: transport, now: { fixedNow })
}

private func bodyObject(_ request: URLRequest) -> [String: Any] {
    guard let body = request.httpBody, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
    return object
}

private func searchIssue(_ key: String, summary: String) -> String {
    #"{"id":"1","key":"\#(key)","fields":{"summary":"\#(summary)","status":{"name":"In progress"},"updated":"2026-11-08T10:00:00.000+0000"}}"#
}

private let inProgressResponse = #"{"issues":[\#(searchIssue("WEB-2744", summary: "Invoice update"))],"isLast":true}"#

private func mentionTransport() -> FakeTransport {
    let mentioning = adfDoc(adfParagraph(adfMention(meAccountId), adfText(" check")))
    return FakeTransport(responses: [
        myselfPath: (200, #"{"accountId":"\#(meAccountId)","displayName":"Test User"}"#),
        searchPath: (200, #"{"issues":[\#(searchIssue("WEB-1", summary: "One")),\#(searchIssue("WEB-2", summary: "Two"))],"isLast":true}"#),
        "/rest/api/3/issue/WEB-1/comment": (200, String(decoding: jiraComments(jiraComment(id: "101", authorId: "other", created: "2026-11-06T09:00:00.000+0000", body: mentioning)), as: UTF8.self)),
        "/rest/api/3/issue/WEB-2/comment": (200, String(decoding: jiraComments(jiraComment(id: "202", authorId: "other", created: "2026-11-08T09:00:00.000+0000", body: mentioning)), as: UTF8.self)),
    ])
}

private func expectOnlyJiraHost(_ transport: FakeTransport, file: StaticString = #file, line: UInt = #line) {
    for request in transport.requests {
        expectEqual(request.url?.scheme, "https", file: file, line: line)
        expectEqual(request.url?.host, "acme.atlassian.net", file: file, line: line)
    }
}

func runJiraClientTests() async {
    await test("Jira client: missing token or email") {
        let transport = FakeTransport()
        await expectError(JiraError.notConfigured) { _ = try await client(transport, token: nil).fetchInProgress() }
        await expectError(JiraError.notConfigured) { _ = try await client(transport, token: nil).fetchMentions() }
        await expectError(JiraError.notConfigured) { _ = try await client(transport, token: "").fetchInProgress() }
        await expectError(JiraError.notConfigured) { _ = try await client(transport, config: jiraConfig(email: "")).fetchInProgress() }
        expectEqual(transport.requests.count, 0)
    }

    await test("Jira client: invalid site") {
        let transport = FakeTransport()
        await expectError(JiraError.notConfigured) { _ = try await client(transport, config: jiraConfig(site: "")).fetchInProgress() }
        await expectError(JiraError.notConfigured) { _ = try await client(transport, config: jiraConfig(site: "  ")).fetchMentions() }
        for site in ["https://x.atlassian.net", "x.atlassian.net/foo", "a b"] {
            await expectError(JiraError.invalidSite) { _ = try await client(transport, config: jiraConfig(site: site)).fetchInProgress() }
            await expectError(JiraError.invalidSite) { _ = try await client(transport, config: jiraConfig(site: site)).fetchMentions() }
        }
        expectEqual(transport.requests.count, 0)
    }

    await test("Jira client: in-progress request") {
        let transport = FakeTransport(responses: [searchPath: (200, inProgressResponse)])
        let config = jiraConfig()
        let issues = try await client(transport, config: config).fetchInProgress()
        expectEqual(issues.map(\.key), ["WEB-2744"])
        expectEqual(transport.requests.count, 1)
        let request = transport.requests[0]
        expectEqual(request.httpMethod, "POST")
        expectEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/search/jql")
        expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("me@example.com:tok".utf8).base64EncodedString())
        expectEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = bodyObject(request)
        expectEqual(body["jql"] as? String, JiraParsing.inProgressJQL(statuses: config.inProgressStatuses))
        expectEqual(body["fields"] as? [String], ["summary", "status", "updated"])
        expectEqual(body["maxResults"] as? Int, 50)
        expectOnlyJiraHost(transport)
    }

    await test("Jira client: ready-to-release request") {
        let transport = FakeTransport(responses: [searchPath: (200, inProgressResponse)])
        var config = jiraConfig()
        config.releaseStatuses = ["Ready to release", "Ready for prod"]
        let issues = try await client(transport, config: config).fetchReadyToRelease()
        expectEqual(issues.map(\.key), ["WEB-2744"])
        let body = transport.requests.first.map(bodyObject) ?? [:]
        expectEqual(body["jql"] as? String, JiraParsing.releaseJQL(statuses: config.releaseStatuses))
        expectEqual(body["maxResults"] as? Int, 50)
        await expectError(JiraError.notConfigured) { _ = try await client(FakeTransport(), token: nil).fetchReadyToRelease() }
    }

    await test("Jira client: HTTP and network errors") {
        let cases: [(Int, JiraError)] = [(401, .unauthorized), (403, .unauthorized), (500, .http(500))]
        for (status, expected) in cases {
            let transport = FakeTransport(responses: [searchPath: (status, "{}")])
            await expectError(expected) { _ = try await client(transport).fetchInProgress() }
        }
        let transport = FakeTransport()
        transport.errors[searchPath] = URLError(.notConnectedToInternet)
        do {
            _ = try await client(transport).fetchInProgress()
            expect(false, "expected a network error")
        } catch JiraError.network(let message) {
            expect(!message.isEmpty, "empty network message")
        }
    }

    await test("Jira client: mentions flow") {
        let transport = mentionTransport()
        let feed = try await client(transport).fetchMentions()
        expectEqual(feed.mentions.map(\.id), ["202", "101"])
        expectEqual(feed.mentions.map(\.issueKey), ["WEB-2", "WEB-1"])
        expectEqual(feed.isComplete, true)
        expectEqual(transport.requests.first?.url?.path, myselfPath)
        expectEqual(transport.requests.first?.httpMethod, "GET")
        let searches = transport.requests(path: searchPath)
        expectEqual(searches.count, 1)
        let body = searches.first.map(bodyObject) ?? [:]
        expectEqual(body["jql"] as? String, JiraParsing.mentionCandidatesJQL(lookbackDays: 7))
        expectEqual(body["maxResults"] as? Int, 15)
        for key in ["WEB-1", "WEB-2"] {
            let requests = transport.requests(path: "/rest/api/3/issue/\(key)/comment")
            expectEqual(requests.count, 1)
            expectEqual(requests.first?.httpMethod, "GET")
            let items = requests.first.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems } ?? []
            expectEqual(items, [URLQueryItem(name: "orderBy", value: "-created"), URLQueryItem(name: "maxResults", value: "30")])
        }
        expectOnlyJiraHost(transport)
    }

    await test("Jira client: mentions respect lookback window") {
        let transport = mentionTransport()
        var config = jiraConfig()
        config.mentionsLookbackDays = 2
        let feed = try await client(transport, config: config).fetchMentions()
        expectEqual(feed.mentions.map(\.id), ["202"])
        expectEqual(feed.isComplete, true)
    }

    await test("Jira client: account id is cached") {
        let transport = mentionTransport()
        let jira = client(transport)
        _ = try await jira.fetchMentions()
        _ = try await jira.fetchMentions()
        expectEqual(transport.requests(path: myselfPath).count, 1)
    }

    await test("Jira client: failed comment request is skipped") {
        let transport = mentionTransport()
        transport.responses["/rest/api/3/issue/WEB-1/comment"] = (500, "{}")
        let feed = try await client(transport).fetchMentions()
        expectEqual(feed.mentions.map(\.id), ["202"])
        expectEqual(feed.isComplete, false)
    }

    await test("Jira client: every comment request failing is an error") {
        let transport = mentionTransport()
        transport.responses["/rest/api/3/issue/WEB-1/comment"] = (500, "{}")
        transport.responses["/rest/api/3/issue/WEB-2/comment"] = (500, "{}")
        await expectError(JiraError.http(500)) { _ = try await client(transport).fetchMentions() }
    }

    await test("Jira client: full candidate page is incomplete") {
        let transport = mentionTransport()
        let keys = (1...15).map { "WEB-\($0)" }
        transport.responses[searchPath] = (200, #"{"issues":[\#(keys.map { searchIssue($0, summary: $0) }.joined(separator: ","))]}"#)
        for key in keys where transport.responses["/rest/api/3/issue/\(key)/comment"] == nil {
            transport.responses["/rest/api/3/issue/\(key)/comment"] = (200, #"{"comments":[]}"#)
        }
        let feed = try await client(transport).fetchMentions()
        expectEqual(feed.mentions.map(\.id), ["202", "101"])
        expectEqual(feed.isComplete, false)
    }

    await test("Jira client: more than 20 mentions are capped and incomplete") {
        let transport = mentionTransport()
        let mentioning = adfDoc(adfParagraph(adfMention(meAccountId)))
        let comments = (1...21).map { jiraComment(id: "9\($0)", authorId: "other", created: "2026-11-07T10:\(String(format: "%02d", $0)):00.000+0000", body: mentioning) }
        transport.responses["/rest/api/3/issue/WEB-1/comment"] = (200, #"{"comments":[\#(comments.joined(separator: ","))]}"#)
        let feed = try await client(transport).fetchMentions()
        expectEqual(feed.mentions.count, 20)
        expectEqual(feed.mentions.first?.id, "202")
        expectEqual(feed.isComplete, false)
    }

    await test("Jira client: rejected token on myself") {
        let transport = mentionTransport()
        transport.responses[myselfPath] = (401, "{}")
        await expectError(JiraError.unauthorized) { _ = try await client(transport).fetchMentions() }
    }

    test("HTTP transport: redirects only stay on the same https host") {
        let origin = URL(string: "https://acme.atlassian.net/rest/api/3/myself")!
        expectEqual(RedirectPolicy.allows(from: origin, to: URL(string: "https://acme.atlassian.net/rest/api/3/user")!), true)
        expectEqual(RedirectPolicy.allows(from: origin, to: URL(string: "https://evil.example.com/rest/api/3/myself")!), false)
        expectEqual(RedirectPolicy.allows(from: origin, to: URL(string: "http://acme.atlassian.net/rest/api/3/myself")!), false)
        expectEqual(RedirectPolicy.allows(from: origin, to: URL(string: "https://ACME.atlassian.net/x")!), true)
        expectEqual(RedirectPolicy.allows(from: nil, to: URL(string: "https://acme.atlassian.net/x")!), false)
        expectEqual(RedirectPolicy.allows(from: origin, to: nil), false)
    }

    test("Jira error: user messages") {
        expectEqual(JiraError.notConfigured.userMessage, "Add your Jira site, email and token in Settings")
        expectEqual(JiraError.invalidSite.userMessage, "Jira site must be a host like example.atlassian.net")
        expectEqual(JiraError.unauthorized.userMessage, "Jira rejected the token — update it in Settings")
        expectEqual(JiraError.http(502).userMessage, "Jira returned HTTP 502")
        expectEqual(JiraError.network("offline").userMessage, "offline")
    }
}
