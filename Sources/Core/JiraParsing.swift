import Foundation

enum JiraParsingError: Error, Equatable, LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        "Unexpected response from Jira"
    }
}

enum JiraParsing {
    private static let snippetLimit = 140

    private static let dateFormatters: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    static func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
                return Date(timeIntervalSince1970: milliseconds / 1000)
            }
        }
        return nil
    }

    static func parseAccountId(_ data: Data) throws -> String {
        guard
            let response = try? JSONDecoder().decode(MyselfResponse.self, from: data),
            let accountId = response.accountId,
            !accountId.isEmpty
        else { throw JiraParsingError.unexpectedResponse }
        return accountId
    }

    static func parseIssues(_ data: Data, site: String) throws -> [JiraIssue] {
        guard
            let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
            let issues = response.issues
        else { throw JiraParsingError.unexpectedResponse }
        return issues.compactMap { issue in
            guard
                let issue,
                let key = issue.key,
                let summary = issue.fields?.summary,
                let status = issue.fields?.status?.name,
                let updated = issue.fields?.updated.flatMap(parseDate),
                let url = browseURL(site: site, key: key, commentId: nil)
            else { return nil }
            return JiraIssue(key: key, summary: summary, status: status, updatedAt: updated, url: url)
        }
    }

    static func parseMentions(_ data: Data, issue: JiraIssue, accountId: String, since: Date, site: String) throws -> [Mention] {
        guard
            let response = try? JSONDecoder().decode(CommentsResponse.self, from: data),
            let comments = response.comments
        else { throw JiraParsingError.unexpectedResponse }
        return comments.compactMap { comment in
            guard
                let comment,
                let id = comment.id,
                let body = comment.body,
                body.mentions(accountId: accountId),
                comment.author?.accountId != accountId,
                let created = comment.created.flatMap(parseDate),
                created >= since,
                let url = browseURL(site: site, key: issue.key, commentId: id)
            else { return nil }
            return Mention(
                id: id,
                issueKey: issue.key,
                issueSummary: issue.summary,
                author: comment.author?.displayName ?? "Unknown",
                snippet: snippet(from: body.plainText),
                createdAt: created,
                url: url
            )
        }
    }

    static func inProgressJQL(statuses: [String]) -> String {
        assignedJQL(statuses: statuses, fallback: "In progress")
    }

    static func releaseJQL(statuses: [String]) -> String {
        assignedJQL(statuses: statuses, fallback: "Ready to release")
    }

    private static func assignedJQL(statuses: [String], fallback: String) -> String {
        let cleaned = statuses
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let list = (cleaned.isEmpty ? [fallback] : cleaned).map(quoted).joined(separator: ", ")
        return "assignee = currentUser() AND status in (\(list)) ORDER BY updated DESC"
    }

    static func mentionCandidatesJQL(lookbackDays: Int) -> String {
        "comment ~ currentUser() AND updated >= -\(lookbackDays)d ORDER BY updated DESC"
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func snippet(from text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > snippetLimit else { return collapsed }
        return String(collapsed.prefix(snippetLimit)) + "…"
    }

    private static func browseURL(site: String, key: String, commentId: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = site
        components.path = "/browse/\(key)"
        if let commentId {
            components.queryItems = [URLQueryItem(name: "focusedCommentId", value: commentId)]
        }
        return components.url
    }

    private struct MyselfResponse: Decodable {
        let accountId: String?
    }

    private struct SearchResponse: Decodable {
        let issues: [Issue?]?
    }

    private struct Issue: Decodable {
        let key: String?
        let fields: Fields?
    }

    private struct Fields: Decodable {
        let summary: String?
        let status: Status?
        let updated: String?
    }

    private struct Status: Decodable {
        let name: String?
    }

    private struct CommentsResponse: Decodable {
        let comments: [Comment?]?
    }

    private struct Comment: Decodable {
        let id: String?
        let author: Author?
        let body: ADFNode?
        let created: String?

        private enum CodingKeys: String, CodingKey {
            case id, author, body, created
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(String.self, forKey: .id)
            author = try? container.decodeIfPresent(Author.self, forKey: .author)
            body = try? container.decodeIfPresent(ADFNode.self, forKey: .body)
            created = try? container.decodeIfPresent(String.self, forKey: .created)
        }
    }

    private struct Author: Decodable {
        let accountId: String?
        let displayName: String?
    }
}
