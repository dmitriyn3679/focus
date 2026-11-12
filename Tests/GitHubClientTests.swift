import Foundation

final class FakeRunner: ProcessRunning {
    var calls: [(executable: String, arguments: [String], timeout: TimeInterval)] = []
    var result: ProcessResult
    var error: Error?

    init(result: ProcessResult = ProcessResult(status: 0, stdout: Data(), stderr: ""), error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        calls.append((executable, arguments, timeout))
        if let error { throw error }
        return result
    }
}

func runGitHubClientTests() async {
    await test("GitHub client: runs gh with both search queries") {
        let runner = FakeRunner(result: ProcessResult(status: 0, stdout: Data(gitHubFixture.utf8), stderr: ""))
        let client = GitHubClient(ghPath: "/opt/homebrew/bin/gh", org: "acme", runner: runner)
        let result = try await client.fetch()
        let expected = try GitHubParsing.parse(Data(gitHubFixture.utf8))
        expectEqual(runner.calls.count, 1)
        let call = runner.calls[0]
        expectEqual(call.executable, "/opt/homebrew/bin/gh")
        expectEqual(Array(call.arguments.prefix(2)), ["api", "graphql"])
        expect(call.arguments.contains("mine=is:pr is:open draft:false author:@me org:acme"), "mine query missing")
        expect(call.arguments.contains("review=is:pr is:open review-requested:@me org:acme"), "review query missing")
        expect(call.arguments.contains { $0.hasPrefix("query=") && $0.contains("fragment PR on PullRequest") && $0.contains("viewer { login }") && $0.contains("__typename") }, "graphql query missing")
        expectEqual(call.timeout, 20)
        expectEqual(result.mine, expected.mine)
        expectEqual(result.review, expected.review)
    }

    await test("GitHub client: non-zero exit becomes failed with stderr") {
        let stderr = "error connecting to api.github.com\ncheck your internet connection"
        let runner = FakeRunner(result: ProcessResult(status: 1, stdout: Data(), stderr: stderr))
        let client = GitHubClient(ghPath: "/x/gh", org: "acme", runner: runner)
        await expectError(GitHubError.failed(stderr)) { _ = try await client.fetch() }
        expectEqual(GitHubError.failed(stderr).userMessage, "error connecting to api.github.com")
    }

    await test("GitHub client: missing gh") {
        let client = GitHubClient(ghPath: "/x/gh", org: "acme", runner: FakeRunner(error: ProcessError.notFound("/x/gh")))
        await expectError(GitHubError.ghNotFound("/x/gh")) { _ = try await client.fetch() }
    }

    await test("GitHub client: timeout") {
        let client = GitHubClient(ghPath: "/x/gh", org: "acme", runner: FakeRunner(error: ProcessError.timedOut))
        await expectError(GitHubError.timedOut) { _ = try await client.fetch() }
    }

    test("GitHub error: user messages") {
        expectEqual(GitHubError.ghNotFound("/x/gh").userMessage, "gh not found at /x/gh")
        expectEqual(GitHubError.timedOut.userMessage, "GitHub request timed out")
        expectEqual(GitHubError.failed("").userMessage, "GitHub request failed")
        expectEqual(GitHubError.failed("\n  \nsecond line").userMessage, "second line")
    }

    await test("Process runner: captures stdout") {
        let result = try await ProcessRunner().run("/bin/echo", ["hi"], timeout: 5)
        expectEqual(result.status, 0)
        expectEqual(String(decoding: result.stdout, as: UTF8.self), "hi\n")
    }

    await test("Process runner: times out") {
        let start = Date()
        await expectError(ProcessError.timedOut) { _ = try await ProcessRunner().run("/bin/sleep", ["5"], timeout: 0.3) }
        expect(Date().timeIntervalSince(start) < 2, "took \(Date().timeIntervalSince(start)) s")
    }

    await test("Process runner: missing executable") {
        await expectError(ProcessError.notFound("/nonexistent/gh")) { _ = try await ProcessRunner().run("/nonexistent/gh", [], timeout: 1) }
    }

    await test("Process runner: large output does not deadlock") {
        let result = try await ProcessRunner().run("/bin/sh", ["-c", "head -c 300000 /dev/zero; head -c 200000 /dev/zero >&2"], timeout: 5)
        expectEqual(result.status, 0)
        expectEqual(result.stdout.count, 300000)
        expectEqual(result.stderr.utf8.count, 200000)
    }

    await test("Process runner: times out when a child keeps the pipe open") {
        let start = Date()
        await expectError(ProcessError.timedOut) { _ = try await ProcessRunner().run("/bin/sh", ["-c", "sleep 3 & exit 0"], timeout: 0.5) }
        expect(Date().timeIntervalSince(start) < 2, "took \(Date().timeIntervalSince(start)) s")
    }

    test("gh locator: configured path wins, then known install paths") {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        expectEqual(GhLocator.resolve(configured: "/custom/gh", candidates: candidates, isExecutable: { $0 == "/custom/gh" }), "/custom/gh")
        expectEqual(GhLocator.resolve(configured: "/opt/homebrew/bin/gh", candidates: candidates, isExecutable: { $0 == "/usr/local/bin/gh" }), "/usr/local/bin/gh")
        expectEqual(GhLocator.resolve(configured: "  ", candidates: candidates, isExecutable: { $0 == "/opt/homebrew/bin/gh" }), "/opt/homebrew/bin/gh")
        expectEqual(GhLocator.resolve(configured: "/missing/gh", candidates: candidates, isExecutable: { _ in false }), "/missing/gh")
        expectEqual(GhLocator.resolve(configured: "", candidates: candidates, isExecutable: { _ in false }), "/opt/homebrew/bin/gh")
    }

    await test("GitHub client: empty org searches every organization") {
        let runner = FakeRunner(result: ProcessResult(status: 0, stdout: Data(gitHubFixture.utf8), stderr: ""))
        _ = try await GitHubClient(ghPath: "/x/gh", org: "  ", runner: runner).fetch()
        let arguments = runner.calls.first?.arguments ?? []
        expect(arguments.contains("mine=is:pr is:open draft:false author:@me"), "mine query: \(arguments)")
        expect(arguments.contains("review=is:pr is:open review-requested:@me"), "review query: \(arguments)")
    }
}
