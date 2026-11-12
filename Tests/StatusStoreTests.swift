import Foundation

final class Gate {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

final class FakeGitHub: GitHubFetching {
    var mine: [PullRequest] = []
    var review: [PullRequest] = []
    var error: Error?
    var calls = 0
    var gate: Gate?

    func fetch() async throws -> (mine: [PullRequest], review: [PullRequest]) {
        calls += 1
        if let gate { await gate.wait() }
        if let error { throw error }
        return (mine, review)
    }
}

final class FakeJira: JiraFetching {
    var issues: [JiraIssue] = []
    var mentions: [Mention] = []
    var mentionsComplete = true
    var inProgressError: Error?
    var mentionsError: Error?
    var inProgressCalls = 0
    var mentionsCalls = 0
    var releaseIssues: [JiraIssue] = []
    var releaseError: Error?
    var releaseCalls = 0

    func fetchInProgress() async throws -> [JiraIssue] {
        inProgressCalls += 1
        if let inProgressError { throw inProgressError }
        return issues
    }

    func fetchReadyToRelease() async throws -> [JiraIssue] {
        releaseCalls += 1
        if let releaseError { throw releaseError }
        return releaseIssues
    }

    func fetchMentions() async throws -> MentionFeed {
        mentionsCalls += 1
        if let mentionsError { throw mentionsError }
        return MentionFeed(mentions: mentions, isComplete: mentionsComplete)
    }
}

final class MemorySeenStore: SeenStoring {
    var ids: Set<String>
    var saves = 0

    init(_ ids: Set<String> = []) {
        self.ids = ids
    }

    func load() -> Set<String> { ids }

    func save(_ ids: Set<String>) {
        self.ids = ids
        saves += 1
    }
}

final class MemoryPRSeenStore: PRSeenStoring {
    var records: [String: Date]
    init(_ records: [String: Date] = [:]) { self.records = records }
    func load() -> [String: Date] { records }
    func save(_ records: [String: Date]) { self.records = records }
}

final class TestClock {
    var current = utc(2026, 11, 9, 12)
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

func makePR(_ number: Int, author: String = "someone", commentsAt: [Date] = []) -> PullRequest {
    PullRequest(number: number, title: "PR \(number)", url: URL(string: "https://github.com/o/r/pull/\(number)")!, repo: "r", repoFullName: "o/r", author: author, updatedAt: utc(2026, 11, 1), reviewDecision: nil, checks: nil, unresolvedThreads: 0, hasConflicts: false, comments: commentsAt.map { PRComment(author: "Alice", isBot: false, createdAt: $0) })
}

func makeIssue(_ key: String) -> JiraIssue {
    JiraIssue(key: key, summary: "Issue \(key)", status: "In progress", updatedAt: utc(2026, 11, 1), url: URL(string: "https://acme.atlassian.net/browse/\(key)")!)
}

func makeMention(_ id: String) -> Mention {
    Mention(id: id, issueKey: "WEB-1", issueSummary: "One", author: "Other", snippet: "hi", createdAt: utc(2026, 11, 8), url: URL(string: "https://acme.atlassian.net/browse/WEB-1?focusedCommentId=\(id)")!)
}

@MainActor
private func makeStore(github: FakeGitHub = FakeGitHub(), jira: FakeJira = FakeJira(), seen: MemorySeenStore = MemorySeenStore(), dismissed: MemorySeenStore = MemorySeenStore(), prSeen: MemoryPRSeenStore = MemoryPRSeenStore(), clock: TestClock = TestClock()) -> StatusStore {
    StatusStore(github: github, jira: jira, seenStore: seen, dismissedStore: dismissed, prSeenStore: prSeen, now: { clock.current })
}

@MainActor
private func populated() -> (FakeGitHub, FakeJira) {
    let github = FakeGitHub()
    github.mine = [makePR(1, author: "me")]
    github.review = [makePR(2), makePR(3)]
    let jira = FakeJira()
    jira.issues = [makeIssue("WEB-10")]
    jira.releaseIssues = [makeIssue("WEB-30"), makeIssue("WEB-31")]
    jira.mentions = [makeMention("a"), makeMention("b"), makeMention("c")]
    return (github, jira)
}

@MainActor
func runStatusStoreTests() async {
    await test("Store: successful refresh fills every section") {
        let (github, jira) = populated()
        let clock = TestClock()
        let store = makeStore(github: github, jira: jira, clock: clock)
        await store.refresh()
        expectEqual(store.myPRs, SectionState(items: github.mine, error: nil))
        expectEqual(store.reviewPRs, SectionState(items: github.review, error: nil))
        expectEqual(store.inProgress, SectionState(items: jira.issues, error: nil))
        expectEqual(store.readyToRelease, SectionState(items: jira.releaseIssues, error: nil))
        expectEqual(store.mentions, SectionState(items: jira.mentions, error: nil))
        expectEqual(store.isRefreshing, false)
        expectEqual(store.lastRefresh, clock.current)
    }

    await test("Store: GitHub failure keeps previous items, Jira still updates") {
        let (github, jira) = populated()
        let store = makeStore(github: github, jira: jira)
        await store.refresh()
        let firstMine = github.mine
        let firstReview = github.review
        github.error = GitHubError.ghNotFound("/x/gh")
        jira.issues = [makeIssue("WEB-20")]
        jira.mentions = [makeMention("z")]
        await store.refresh()
        expectEqual(store.myPRs, SectionState(items: firstMine, error: "gh not found at /x/gh"))
        expectEqual(store.reviewPRs, SectionState(items: firstReview, error: "gh not found at /x/gh"))
        expectEqual(store.inProgress, SectionState(items: [makeIssue("WEB-20")], error: nil))
        expectEqual(store.mentions, SectionState(items: [makeMention("z")], error: nil))
    }

    await test("Store: Jira errors map to user messages") {
        let (github, jira) = populated()
        jira.inProgressError = JiraError.notConfigured
        jira.mentionsError = JiraError.unauthorized
        let store = makeStore(github: github, jira: jira)
        await store.refresh()
        expectEqual(store.inProgress.error, "Add your Jira site, email and token in Settings")
        expectEqual(store.mentions.error, "Jira rejected the token — update it in Settings")
        expectEqual(store.myPRs, SectionState(items: github.mine, error: nil))
        expectEqual(store.reviewPRs, SectionState(items: github.review, error: nil))
    }

    await test("Store: ready-to-release fails on its own") {
        let (github, jira) = populated()
        let store = makeStore(github: github, jira: jira)
        await store.refresh()
        jira.releaseError = JiraError.unauthorized
        jira.issues = [makeIssue("WEB-11")]
        await store.refresh()
        expectEqual(store.readyToRelease, SectionState(items: [makeIssue("WEB-30"), makeIssue("WEB-31")], error: "Jira rejected the token — update it in Settings"))
        expectEqual(store.inProgress, SectionState(items: [makeIssue("WEB-11")], error: nil))
    }

    await test("Store: other errors use localized description") {
        let (github, jira) = populated()
        jira.inProgressError = JiraParsingError.unexpectedResponse
        let store = makeStore(github: github, jira: jira)
        await store.refresh()
        expectEqual(store.inProgress.error, "Unexpected response from Jira")
    }

    await test("Store: error clears after a successful refresh") {
        let (github, jira) = populated()
        github.error = GitHubError.timedOut
        let store = makeStore(github: github, jira: jira)
        await store.refresh()
        expectEqual(store.myPRs.error, "GitHub request timed out")
        github.error = nil
        await store.refresh()
        expectEqual(store.myPRs, SectionState(items: github.mine, error: nil))
    }

    await test("Store: concurrent refreshes share one fetch") {
        let (github, jira) = populated()
        let gate = Gate()
        github.gate = gate
        let store = makeStore(github: github, jira: jira)
        let first = Task { await store.refresh() }
        while github.calls == 0 { await Task.yield() }
        expectEqual(store.isRefreshing, true)
        let second = Task { await store.refresh() }
        for _ in 0..<20 { await Task.yield() }
        gate.open()
        await first.value
        await second.value
        expectEqual(github.calls, 1)
        expectEqual(jira.inProgressCalls, 1)
        expectEqual(jira.mentionsCalls, 1)
        expectEqual(jira.releaseCalls, 1)
        expectEqual(store.isRefreshing, false)
        await store.refresh()
        expectEqual(github.calls, 2)
    }

    await test("Store: refreshIfStale") {
        let (github, jira) = populated()
        let clock = TestClock()
        let store = makeStore(github: github, jira: jira, clock: clock)
        await store.refreshIfStale(olderThan: 60)
        expectEqual(github.calls, 1)
        clock.advance(30)
        await store.refreshIfStale(olderThan: 60)
        expectEqual(github.calls, 1)
        clock.advance(31)
        await store.refreshIfStale(olderThan: 60)
        expectEqual(github.calls, 2)
    }

    await test("Store: badge counts review requests and unseen mentions") {
        let (github, jira) = populated()
        let seen = MemorySeenStore()
        let store = makeStore(github: github, jira: jira, seen: seen)
        await store.refresh()
        expectEqual(store.badgeCount, 5)
        expectEqual(store.unseenMentionCount, 3)
        store.markSeen("b")
        expectEqual(store.badgeCount, 4)
        expectEqual(store.unseenMentionCount, 2)
        expectEqual(seen.ids, ["b"])
        store.markAllSeen()
        expectEqual(store.badgeCount, 2)
        expectEqual(store.unseenMentionCount, 0)
        expectEqual(seen.ids, ["a", "b", "c"])
    }

    await test("Store: seen ids are loaded at init") {
        let (github, jira) = populated()
        let store = makeStore(github: github, jira: jira, seen: MemorySeenStore(["a", "c"]))
        expectEqual(store.seenMentionIDs, ["a", "c"])
        await store.refresh()
        expectEqual(store.unseenMentionCount, 1)
    }

    await test("Store: seen ids are pruned only after a successful mentions fetch") {
        let (github, jira) = populated()
        jira.mentions = [makeMention("a"), makeMention("c")]
        let seen = MemorySeenStore(["a", "b"])
        let store = makeStore(github: github, jira: jira, seen: seen)
        await store.refresh()
        expectEqual(seen.ids, ["a"])
        expectEqual(store.seenMentionIDs, ["a"])

        let partialJira = FakeJira()
        partialJira.mentions = [makeMention("a")]
        partialJira.mentionsComplete = false
        let partialSeen = MemorySeenStore(["a", "b"])
        let partialStore = makeStore(github: github, jira: partialJira, seen: partialSeen)
        await partialStore.refresh()
        expectEqual(partialStore.mentions.items, [makeMention("a")])
        expectEqual(partialSeen.ids, ["a", "b"])
        expectEqual(partialStore.seenMentionIDs, ["a", "b"])

        let failingJira = FakeJira()
        failingJira.mentionsError = JiraError.http(500)
        let keptSeen = MemorySeenStore(["a", "b"])
        let failingStore = makeStore(github: github, jira: failingJira, seen: keptSeen)
        await failingStore.refresh()
        expectEqual(keptSeen.ids, ["a", "b"])
        expectEqual(failingStore.seenMentionIDs, ["a", "b"])
    }

    await test("Store: reconfigure swaps fetchers") {
        let (github, jira) = populated()
        let store = makeStore(github: github, jira: jira)
        let (newGitHub, newJira) = populated()
        newGitHub.mine = [makePR(99)]
        store.reconfigure(github: newGitHub, jira: newJira)
        await store.refresh()
        expectEqual(github.calls, 0)
        expectEqual(jira.inProgressCalls, 0)
        expectEqual(jira.mentionsCalls, 0)
        expectEqual(newGitHub.calls, 1)
        expectEqual(newJira.inProgressCalls, 1)
        expectEqual(newJira.mentionsCalls, 1)
        expectEqual(store.myPRs.items, [makePR(99)])
    }

    await test("Store: reconfigure during a refresh reruns with the new fetchers") {
        let (github, jira) = populated()
        let gate = Gate()
        github.gate = gate
        let store = makeStore(github: github, jira: jira)
        let first = Task { await store.refresh() }
        while github.calls == 0 { await Task.yield() }
        let (newGitHub, newJira) = populated()
        newGitHub.mine = [makePR(77)]
        store.reconfigure(github: newGitHub, jira: newJira)
        let second = Task { await store.refresh() }
        for _ in 0..<20 { await Task.yield() }
        gate.open()
        await first.value
        await second.value
        expectEqual(github.calls, 1)
        expectEqual(newGitHub.calls, 1)
        expectEqual(newJira.inProgressCalls, 1)
        expectEqual(newJira.mentionsCalls, 1)
        expectEqual(store.myPRs.items, [makePR(77)])
        expectEqual(store.isRefreshing, false)
    }

    await test("Store: dismissed mentions are hidden and leave the badge") {
        let (github, jira) = populated()
        let dismissed = MemorySeenStore()
        let store = makeStore(github: github, jira: jira, dismissed: dismissed)
        await store.refresh()
        store.dismissMention("b")
        expectEqual(store.visibleMentions, SectionState(items: [makeMention("a"), makeMention("c")], error: nil))
        expectEqual(store.unseenMentionCount, 2)
        expectEqual(store.badgeCount, 4)
        expectEqual(dismissed.ids, ["b"])
        expectEqual(store.mentions.items.count, 3)
    }

    await test("Store: clear all hides every visible mention") {
        let (github, jira) = populated()
        let dismissed = MemorySeenStore(["a"])
        let store = makeStore(github: github, jira: jira, dismissed: dismissed)
        await store.refresh()
        store.dismissAllMentions()
        expectEqual(store.visibleMentions.items, [])
        expectEqual(store.unseenMentionCount, 0)
        expectEqual(store.badgeCount, 2)
        expectEqual(dismissed.ids, ["a", "b", "c"])
    }

    await test("Store: dismissed ids load at init and new mentions still show") {
        let (github, jira) = populated()
        let store = makeStore(github: github, jira: jira, dismissed: MemorySeenStore(["a", "c"]))
        expectEqual(store.dismissedMentionIDs, ["a", "c"])
        await store.refresh()
        expectEqual(store.visibleMentions.items.map(\.id), ["b"])
        jira.mentions = [makeMention("d"), makeMention("a")]
        await store.refresh()
        expectEqual(store.visibleMentions.items.map(\.id), ["d"])
    }

    await test("Store: dismissed ids are pruned only from a complete feed") {
        let (github, jira) = populated()
        jira.mentions = [makeMention("a")]
        jira.mentionsComplete = false
        let dismissed = MemorySeenStore(["a", "old"])
        let store = makeStore(github: github, jira: jira, dismissed: dismissed)
        await store.refresh()
        expectEqual(dismissed.ids, ["a", "old"])
        jira.mentionsComplete = true
        await store.refresh()
        expectEqual(dismissed.ids, ["a"])
        expectEqual(store.dismissedMentionIDs, ["a"])
    }

    await test("Store: visible mentions keep the section error") {
        let (github, jira) = populated()
        let store = makeStore(github: github, jira: jira, dismissed: MemorySeenStore(["a"]))
        await store.refresh()
        jira.mentionsError = JiraError.http(500)
        await store.refresh()
        expectEqual(store.visibleMentions, SectionState(items: [makeMention("b"), makeMention("c")], error: "Jira returned HTTP 500"))
    }

    await test("Store: comments present at first sight are not new") {
        let (github, jira) = populated()
        let pr = makePR(5, commentsAt: [utc(2026, 11, 10, 9)])
        github.mine = [pr]
        let prSeen = MemoryPRSeenStore()
        let store = makeStore(github: github, jira: jira, prSeen: prSeen)
        await store.refresh()
        expectEqual(store.hasNewComments(pr), false)
        expectEqual(store.newCommentPRCount, 0)
        expectEqual(prSeen.records, [pr.id: utc(2026, 11, 10, 9)])
    }

    await test("Store: a later comment marks the PR new until it is opened") {
        let (github, jira) = populated()
        github.mine = [makePR(5, commentsAt: [utc(2026, 11, 10, 9)])]
        let prSeen = MemoryPRSeenStore()
        let store = makeStore(github: github, jira: jira, prSeen: prSeen)
        await store.refresh()
        let updated = makePR(5, commentsAt: [utc(2026, 11, 10, 9), utc(2026, 11, 10, 15)])
        github.mine = [updated]
        await store.refresh()
        expectEqual(store.hasNewComments(updated), true)
        expectEqual(store.newCommentPRCount, 1)
        expectEqual(store.badgeCount, 2 + 3 + 1)
        store.markPRSeen(updated)
        expectEqual(store.hasNewComments(updated), false)
        expectEqual(store.badgeCount, 2 + 3)
        expectEqual(prSeen.records, [updated.id: utc(2026, 11, 10, 15)])
    }

    await test("Store: first comment on a quiet PR is new") {
        let (github, jira) = populated()
        github.mine = [makePR(6)]
        let store = makeStore(github: github, jira: jira)
        await store.refresh()
        let commented = makePR(6, commentsAt: [utc(2026, 11, 10, 15)])
        github.mine = [commented]
        await store.refresh()
        expectEqual(store.hasNewComments(commented), true)
    }

    await test("Store: saved PR records are respected and pruned only on success") {
        let (github, jira) = populated()
        let pr = makePR(7, commentsAt: [utc(2026, 11, 10, 15)])
        github.mine = [pr]
        let prSeen = MemoryPRSeenStore([pr.id: utc(2026, 11, 10, 9), "https://github.com/o/r/pull/999": utc(2026, 1, 1)])
        let store = makeStore(github: github, jira: jira, prSeen: prSeen)
        github.error = GitHubError.timedOut
        await store.refresh()
        expectEqual(prSeen.records.count, 2)
        github.error = nil
        await store.refresh()
        expectEqual(store.hasNewComments(pr), true)
        expectEqual(prSeen.records, [pr.id: utc(2026, 11, 10, 9)])
    }

    test("PR seen file store: round-trip and unreadable file") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("status-widget-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/seen-prs.json")
        let store = FilePRSeenStore(url: url)
        expectEqual(store.load(), [:])
        store.save(["https://github.com/o/r/pull/1": utc(2026, 11, 10, 15, 30, 5)])
        expectEqual(store.load(), ["https://github.com/o/r/pull/1": utc(2026, 11, 10, 15, 30, 5)])
        try Data("garbage".utf8).write(to: url)
        expectEqual(store.load(), [:])
    }

    test("Seen file store: round-trip and unreadable file") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("status-widget-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/seen-mentions.json")
        let store = FileSeenStore(url: url)
        expectEqual(store.load(), [])
        store.save(["x", "y"])
        expectEqual(store.load(), ["x", "y"])
        try Data("garbage".utf8).write(to: url)
        expectEqual(store.load(), [])
        expectEqual(FileSeenStore.defaultURL.path, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/status-widget/seen-mentions.json").path)
    }
}
