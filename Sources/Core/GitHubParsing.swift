import Foundation

enum GitHubParsing {
    static func parse(_ data: Data, policy: CommentPolicy = CommentPolicy()) throws -> (mine: [PullRequest], review: [PullRequest]) {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GitHubError.failed("Unexpected response from GitHub")
        }
        if let errors = response.errors, !errors.isEmpty {
            throw GitHubError.failed(errors.compactMap(\.message).filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        guard let payload = response.data else {
            throw GitHubError.failed("Unexpected response from GitHub")
        }
        let formatter = ISO8601DateFormatter()
        let context = CommentContext(policy: policy, viewer: payload.viewer?.login, formatter: formatter)
        return (
            mine: (payload.mine?.nodes ?? []).compactMap { $0 }.compactMap { pullRequest(from: $0, context: context) },
            review: (payload.review?.nodes ?? []).compactMap { $0 }.compactMap { pullRequest(from: $0, context: context) }
        )
    }

    private struct CommentContext {
        let botLogins: Set<String>
        let ignoredLogins: Set<String>
        let viewer: String?
        let formatter: ISO8601DateFormatter

        init(policy: CommentPolicy, viewer: String?, formatter: ISO8601DateFormatter) {
            botLogins = Set(policy.botLogins.map { $0.lowercased() })
            ignoredLogins = Set(policy.ignoredLogins.map { $0.lowercased() })
            self.viewer = viewer?.lowercased()
            self.formatter = formatter
        }

        func comment(from node: CommentNode?) -> PRComment? {
            guard
                let node,
                let login = node.author?.login,
                !login.isEmpty,
                let created = node.createdAt.flatMap(formatter.date(from:))
            else { return nil }
            let key = login.lowercased()
            guard key != viewer, !ignoredLogins.contains(key) else { return nil }
            return PRComment(author: login, isBot: node.author?.typename == "Bot" || botLogins.contains(key), createdAt: created)
        }
    }

    private static func pullRequest(from node: Node, context: CommentContext) -> PullRequest? {
        let formatter = context.formatter
        guard
            let number = node.number,
            let title = node.title,
            let urlString = node.url,
            let url = URL(string: urlString),
            let updatedString = node.updatedAt,
            let updatedAt = formatter.date(from: updatedString),
            let nameWithOwner = node.repository?.nameWithOwner
        else { return nil }
        let repo = nameWithOwner.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? nameWithOwner
        let state = node.commits?.nodes?.last?.commit?.statusCheckRollup?.state
        let threads = (node.reviewThreads?.nodes ?? []).compactMap { $0 }
        let conversation = (node.comments?.nodes ?? []).compactMap(context.comment(from:))
        let threadComments = threads
            .filter { $0.isResolved == false }
            .flatMap { ($0.comments?.nodes ?? []).compactMap(context.comment(from:)) }
        return PullRequest(
            number: number,
            title: title,
            url: url,
            repo: repo,
            repoFullName: nameWithOwner,
            author: node.author?.login,
            updatedAt: updatedAt,
            reviewDecision: node.reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
            checks: state.flatMap(checksState(from:)),
            unresolvedThreads: threads.filter { $0.isResolved == false }.count,
            hasConflicts: node.mergeable == "CONFLICTING",
            comments: conversation + threadComments
        )
    }

    private static func checksState(from state: String) -> ChecksState? {
        switch state {
        case "SUCCESS": return .passed
        case "FAILURE", "ERROR": return .failed
        case "PENDING", "EXPECTED": return .running
        default: return nil
        }
    }

    private struct Response: Decodable {
        let data: Payload?
        let errors: [GraphQLError]?
    }

    private struct GraphQLError: Decodable {
        let message: String?
    }

    private struct Payload: Decodable {
        let viewer: Viewer?
        let mine: Connection?
        let review: Connection?
    }

    private struct Connection: Decodable {
        let nodes: [Node?]?
    }

    private struct Node: Decodable {
        let number: Int?
        let title: String?
        let url: String?
        let updatedAt: String?
        let reviewDecision: String?
        let mergeable: String?
        let author: Author?
        let repository: Repository?
        let reviewThreads: Threads?
        let commits: Commits?
        let comments: Comments?
    }

    private struct Viewer: Decodable { let login: String? }
    private struct Comments: Decodable { let nodes: [CommentNode?]? }

    private struct CommentNode: Decodable {
        let author: CommentAuthorNode?
        let createdAt: String?
    }

    private struct CommentAuthorNode: Decodable {
        let typename: String?
        let login: String?

        private enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case login
        }
    }

    private struct Author: Decodable { let login: String? }
    private struct Repository: Decodable { let nameWithOwner: String? }
    private struct Threads: Decodable { let nodes: [Thread?]? }

    private struct Thread: Decodable {
        let isResolved: Bool?
        let comments: Comments?
    }
    private struct Commits: Decodable { let nodes: [CommitNode]? }
    private struct CommitNode: Decodable { let commit: Commit? }
    private struct Commit: Decodable { let statusCheckRollup: Rollup? }
    private struct Rollup: Decodable { let state: String? }
}
