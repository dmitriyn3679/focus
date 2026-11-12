import Foundation

enum GitHubError: Error, Equatable {
    case ghNotFound(String)
    case failed(String)
    case timedOut

    var userMessage: String {
        switch self {
        case .ghNotFound(let path):
            return "gh not found at \(path)"
        case .failed(let text):
            let line = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return line ?? "GitHub request failed"
        case .timedOut:
            return "GitHub request timed out"
        }
    }
}

protocol GitHubFetching {
    func fetch() async throws -> (mine: [PullRequest], review: [PullRequest])
}

struct GitHubClient: GitHubFetching {
    static let query = """
    query($mine: String!, $review: String!) {
      viewer { login }
      mine: search(query: $mine, type: ISSUE, first: 30) { nodes { ...PR } }
      review: search(query: $review, type: ISSUE, first: 30) { nodes { ...PR } }
    }
    fragment PR on PullRequest {
      number title url updatedAt reviewDecision mergeable
      author { login }
      repository { nameWithOwner }
      reviewThreads(first: 100) { nodes { isResolved comments(last: 20) { nodes { author { __typename login } createdAt } } } }
      comments(last: 50) { nodes { author { __typename login } createdAt } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    private let ghPath: String
    private let org: String
    private let runner: ProcessRunning
    private let commentPolicy: CommentPolicy

    init(ghPath: String, org: String, runner: ProcessRunning, commentPolicy: CommentPolicy = CommentPolicy()) {
        self.ghPath = ghPath
        self.org = org
        self.runner = runner
        self.commentPolicy = commentPolicy
    }

    func fetch() async throws -> (mine: [PullRequest], review: [PullRequest]) {
        let trimmedOrg = org.trimmingCharacters(in: .whitespaces)
        let orgFilter = trimmedOrg.isEmpty ? "" : " org:\(trimmedOrg)"
        let arguments = [
            "api", "graphql",
            "-f", "query=\(Self.query)",
            "-f", "mine=is:pr is:open draft:false author:@me\(orgFilter)",
            "-f", "review=is:pr is:open review-requested:@me\(orgFilter)",
        ]
        let result: ProcessResult
        do {
            result = try await runner.run(ghPath, arguments, timeout: 20)
        } catch ProcessError.notFound(let path) {
            throw GitHubError.ghNotFound(path)
        } catch ProcessError.timedOut {
            throw GitHubError.timedOut
        } catch {
            throw GitHubError.failed(error.localizedDescription)
        }
        guard result.status == 0 else {
            throw GitHubError.failed(result.stderr)
        }
        return try GitHubParsing.parse(result.stdout, policy: commentPolicy)
    }
}

enum GhLocator {
    static let knownPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    static func resolve(
        configured: String,
        candidates: [String] = knownPaths,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, isExecutable(trimmed) {
            return trimmed
        }
        if let found = candidates.first(where: isExecutable) {
            return found
        }
        return trimmed.isEmpty ? (candidates.first ?? "gh") : trimmed
    }
}
