import Foundation

enum ReviewDecision: String {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum ChecksState {
    case passed, failed, running
}

struct PRComment: Equatable {
    let author: String
    let isBot: Bool
    let createdAt: Date
}

struct CommentAuthor: Equatable {
    let login: String
    let isBot: Bool
    let count: Int
}

struct CommentCounts: Equatable {
    let people: Int
    let bots: Int
}

struct CommentPolicy: Equatable {
    var botLogins: [String]
    var ignoredLogins: [String]

    init(botLogins: [String] = [], ignoredLogins: [String] = []) {
        self.botLogins = botLogins
        self.ignoredLogins = ignoredLogins
    }
}

struct PullRequest: Equatable, Identifiable {
    var id: String
    let number: Int
    let title: String
    let url: URL
    let repo: String
    let repoFullName: String
    let author: String?
    let updatedAt: Date
    let reviewDecision: ReviewDecision?
    let checks: ChecksState?
    let unresolvedThreads: Int
    let hasConflicts: Bool
    let comments: [PRComment]

    init(number: Int, title: String, url: URL, repo: String, repoFullName: String, author: String?, updatedAt: Date, reviewDecision: ReviewDecision?, checks: ChecksState?, unresolvedThreads: Int, hasConflicts: Bool, comments: [PRComment] = []) {
        self.id = url.absoluteString
        self.number = number
        self.title = title
        self.url = url
        self.repo = repo
        self.repoFullName = repoFullName
        self.author = author
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.unresolvedThreads = unresolvedThreads
        self.hasConflicts = hasConflicts
        self.comments = comments
    }

    var needsAttention: Bool {
        unresolvedThreads > 0
    }

    var latestCommentAt: Date? {
        comments.map(\.createdAt).max()
    }

    var commentCounts: CommentCounts {
        let bots = comments.filter(\.isBot).count
        return CommentCounts(people: comments.count - bots, bots: bots)
    }

    var commentAuthors: [CommentAuthor] {
        var order: [String] = []
        var groups: [String: (login: String, isBot: Bool, count: Int)] = [:]
        for comment in comments {
            let key = comment.author.lowercased()
            if let group = groups[key] {
                groups[key] = (group.login, group.isBot, group.count + 1)
            } else {
                order.append(key)
                groups[key] = (comment.author, comment.isBot, 1)
            }
        }
        return order.enumerated()
            .compactMap { index, key in groups[key].map { (index, CommentAuthor(login: $0.login, isBot: $0.isBot, count: $0.count)) } }
            .sorted { lhs, rhs in
                if lhs.1.isBot != rhs.1.isBot { return !lhs.1.isBot }
                if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
                return lhs.0 < rhs.0
            }
            .map(\.1)
    }
}

struct SectionState<Item: Equatable>: Equatable {
    var items: [Item] = []
    var error: String? = nil
}

struct JiraIssue: Equatable, Identifiable {
    var id: String
    let key: String
    let summary: String
    let status: String
    let updatedAt: Date
    let url: URL

    init(key: String, summary: String, status: String, updatedAt: Date, url: URL) {
        self.id = key
        self.key = key
        self.summary = summary
        self.status = status
        self.updatedAt = updatedAt
        self.url = url
    }
}

struct Mention: Equatable, Identifiable {
    let id: String
    let issueKey: String
    let issueSummary: String
    let author: String
    let snippet: String
    let createdAt: Date
    let url: URL
}

struct MentionFeed: Equatable {
    var mentions: [Mention]
    var isComplete: Bool
}
