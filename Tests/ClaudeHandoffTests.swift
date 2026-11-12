import Foundation

private func makeClone(_ root: URL, _ folder: String, remotes: [(String, String)]) throws {
    let git = root.appendingPathComponent(folder).appendingPathComponent(".git")
    try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
    var text = "[core]\n\trepositoryformatversion = 0\n"
    for (name, url) in remotes {
        text += "[remote \"\(name)\"]\n\turl = \(url)\n\tfetch = +refs/heads/*:refs/remotes/\(name)/*\n"
    }
    try Data(text.utf8).write(to: git.appendingPathComponent("config"))
}

private func withRepos(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("status-widget-repos-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeClone(root, "web", remotes: [("origin", "git@github.com:acme/web.git")])
    try makeClone(root, "web-mcp", remotes: [("origin", "git@github.com:acme/mcp-seller.git")])
    try makeClone(root, "https-clone", remotes: [("origin", "https://github.com/Acme/Main-UI")])
    try makeClone(root, "fork", remotes: [("upstream", "git@github.com:acme/youproxy.git"), ("origin", "git@github.com:someone/youproxy.git")])
    try FileManager.default.createDirectory(at: root.appendingPathComponent("no-git"), withIntermediateDirectories: true)
    try body(root)
}

private let reviewPR = PullRequest(
    number: 1521,
    title: "WEB-2858 Update dashboard button logic",
    url: URL(string: "https://github.com/acme/web/pull/1521")!,
    repo: "web",
    repoFullName: "acme/web",
    author: "alice",
    updatedAt: utc(2026, 7, 17),
    reviewDecision: nil,
    checks: nil,
    unresolvedThreads: 0,
    hasConflicts: false
)

private let reviewBlock = "https://github.com/acme/web/pull/1521"

func runClaudeHandoffTests() async {
    test("Repo locator: finds clones by origin remote") {
        try withRepos { root in
            expectEqual(RepoLocator.localClone(of: "acme/web", in: root)?.lastPathComponent, "web")
            expectEqual(RepoLocator.localClone(of: "acme/mcp-seller", in: root)?.lastPathComponent, "web-mcp")
            expectEqual(RepoLocator.localClone(of: "acme/main-ui", in: root)?.lastPathComponent, "https-clone")
            expectEqual(RepoLocator.localClone(of: "acme/youproxy", in: root), nil)
            expectEqual(RepoLocator.localClone(of: "acme/unknown", in: root), nil)
            expectEqual(RepoLocator.localClone(of: "acme/web", in: root.appendingPathComponent("missing")), nil)
        }
    }

    test("Repo locator: expands the configured folder") {
        let home = FileManager.default.homeDirectoryForCurrentUser
        expectEqual(RepoLocator.directoryURL(from: "~/Projects")?.path, home.appendingPathComponent("Projects").path)
        expectEqual(RepoLocator.directoryURL(from: "  /tmp/repos  ")?.path, "/tmp/repos")
        expectEqual(RepoLocator.directoryURL(from: ""), nil)
        expectEqual(RepoLocator.directoryURL(from: "relative/path"), nil)
    }

    test("My PR needs attention only while review threads are unresolved") {
        func pr(decision: ReviewDecision?, unresolved: Int) -> PullRequest {
            PullRequest(number: 1, title: "t", url: URL(string: "https://github.com/o/r/pull/1")!, repo: "r", repoFullName: "o/r", author: "me", updatedAt: utc(2026, 1, 1), reviewDecision: decision, checks: nil, unresolvedThreads: unresolved, hasConflicts: false)
        }
        expectEqual(pr(decision: nil, unresolved: 0).needsAttention, false)
        expectEqual(pr(decision: .approved, unresolved: 0).needsAttention, false)
        expectEqual(pr(decision: .changesRequested, unresolved: 0).needsAttention, false)
        expectEqual(pr(decision: nil, unresolved: 2).needsAttention, true)
        expectEqual(pr(decision: .approved, unresolved: 1).needsAttention, true)
    }

    test("Claude handoff: message without prompt is only the PR link") {
        expectEqual(ClaudeHandoff.message(for: reviewPR, prompt: "  \n "), reviewBlock)
    }

    test("Claude handoff: prompt goes first") {
        expectEqual(ClaudeHandoff.message(for: reviewPR, prompt: "  Review it\ncarefully\n"), "Review it\ncarefully\n\n" + reviewBlock)
    }

    test("Claude handoff: long prompt is cut and the PR block is kept") {
        let message = ClaudeHandoff.message(for: reviewPR, prompt: String(repeating: "p", count: 6000))
        expectEqual(message.count, ClaudeHandoff.maxMessageLength)
        expect(message.hasSuffix("\n\n" + reviewBlock), "PR block lost")
        expect(message.hasPrefix("ppp"), "prompt lost")
    }

    test("Claude handoff: release check lists every issue") {
        let issues = [makeIssue("WEB-3354"), makeIssue("WEB-1309")]
        let list = "WEB-3354, WEB-1309"
        expectEqual(ClaudeHandoff.releaseMessage(for: issues, prompt: " Check prod \n"), "Check prod\n\n" + list)
        expectEqual(ClaudeHandoff.releaseMessage(for: issues, prompt: ""), list)
    }

    test("Claude handoff: long release check keeps the prompt and whole issue keys") {
        let issues = (1...900).map { makeIssue("WEB-\($0)") }
        let message = ClaudeHandoff.releaseMessage(for: issues, prompt: String(repeating: "p", count: 6000))
        expect(message.count <= ClaudeHandoff.maxMessageLength, "too long: \(message.count)")
        expect(message.hasPrefix(String(repeating: "p", count: 2500) + "\n\nWEB-1, WEB-2, "), "prompt must be kept up to 2500 characters, then the keys")
        expect(!message.hasPrefix(String(repeating: "p", count: 2501)), "prompt must be capped")
        expect(!message.contains("Issue "), "only keys are listed")
        let tail = message.components(separatedBy: ", ").last ?? ""
        expect(tail.hasPrefix("+") && tail.hasSuffix(" more"), "missing overflow marker: \(tail)")
    }

    test("Claude handoff: link opens a new Code session in the folder") {
        let message = "Check a+b & c=d #x?\nnext line"
        let url = ClaudeHandoff.url(message: message, folder: URL(fileURLWithPath: "/Users/me/Projects/web"))
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        expectEqual(components?.scheme, "claude")
        expectEqual(components?.host, "code")
        expectEqual(components?.path, "/new")
        expectEqual(components?.queryItems, [URLQueryItem(name: "q", value: message), URLQueryItem(name: "folder", value: "/Users/me/Projects/web")])
        let raw = components?.percentEncodedQuery ?? ""
        expect(!raw.contains("+"), "raw + would decode as a space: \(raw)")
        expectEqual(raw.split(separator: "&").count, 2)
    }

    test("Claude handoff: link without folder") {
        let url = ClaudeHandoff.url(message: "hi", folder: nil)
        expectEqual(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems, [URLQueryItem(name: "q", value: "hi")])
    }
}
