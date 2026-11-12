import Combine
import Foundation

@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var myPRs = SectionState<PullRequest>()
    @Published private(set) var reviewPRs = SectionState<PullRequest>()
    @Published private(set) var inProgress = SectionState<JiraIssue>()
    @Published private(set) var readyToRelease = SectionState<JiraIssue>()
    @Published private(set) var mentions = SectionState<Mention>()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var seenMentionIDs: Set<String>
    @Published private(set) var dismissedMentionIDs: Set<String>
    @Published private(set) var prCommentSeen: [String: Date]

    private var github: GitHubFetching
    private var jira: JiraFetching
    private let seenStore: SeenStoring
    private let dismissedStore: SeenStoring
    private let prSeenStore: PRSeenStoring
    private let now: () -> Date
    private var inFlight: Task<Void, Never>?
    private var needsRerun = false

    init(github: GitHubFetching, jira: JiraFetching, seenStore: SeenStoring, dismissedStore: SeenStoring, prSeenStore: PRSeenStoring, now: @escaping () -> Date = Date.init) {
        self.github = github
        self.jira = jira
        self.seenStore = seenStore
        self.dismissedStore = dismissedStore
        self.prSeenStore = prSeenStore
        self.now = now
        self.seenMentionIDs = seenStore.load()
        self.dismissedMentionIDs = dismissedStore.load()
        self.prCommentSeen = prSeenStore.load()
    }

    var visibleMentions: SectionState<Mention> {
        SectionState(items: mentions.items.filter { !dismissedMentionIDs.contains($0.id) }, error: mentions.error)
    }

    var unseenMentionCount: Int {
        visibleMentions.items.filter { !seenMentionIDs.contains($0.id) }.count
    }

    var newCommentPRCount: Int {
        myPRs.items.filter(hasNewComments).count
    }

    var badgeCount: Int {
        reviewPRs.items.count + unseenMentionCount + newCommentPRCount
    }

    func hasNewComments(_ pr: PullRequest) -> Bool {
        guard let latest = pr.latestCommentAt, let seen = prCommentSeen[pr.id] else { return false }
        return latest > seen
    }

    func markPRSeen(_ pr: PullRequest) {
        guard let latest = pr.latestCommentAt, (prCommentSeen[pr.id] ?? .distantPast) < latest else { return }
        prCommentSeen[pr.id] = latest
        prSeenStore.save(prCommentSeen)
    }

    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        isRefreshing = true
        let task = Task { await performRefresh() }
        inFlight = task
        await task.value
    }

    func refreshIfStale(olderThan seconds: TimeInterval) async {
        if let lastRefresh, now().timeIntervalSince(lastRefresh) <= seconds {
            return
        }
        await refresh()
    }

    func reconfigure(github: GitHubFetching, jira: JiraFetching) {
        self.github = github
        self.jira = jira
        if inFlight != nil {
            needsRerun = true
        }
    }

    func markSeen(_ id: String) {
        guard !seenMentionIDs.contains(id) else { return }
        seenMentionIDs.insert(id)
        seenStore.save(seenMentionIDs)
    }

    func markAllSeen() {
        let updated = seenMentionIDs.union(visibleMentions.items.map(\.id))
        guard updated != seenMentionIDs else { return }
        seenMentionIDs = updated
        seenStore.save(updated)
    }

    func dismissMention(_ id: String) {
        guard !dismissedMentionIDs.contains(id) else { return }
        dismissedMentionIDs.insert(id)
        dismissedStore.save(dismissedMentionIDs)
    }

    func dismissAllMentions() {
        let updated = dismissedMentionIDs.union(mentions.items.map(\.id))
        guard updated != dismissedMentionIDs else { return }
        dismissedMentionIDs = updated
        dismissedStore.save(updated)
    }

    private enum Outcome {
        case github(Result<(mine: [PullRequest], review: [PullRequest]), Error>)
        case inProgress(Result<[JiraIssue], Error>)
        case readyToRelease(Result<[JiraIssue], Error>)
        case mentions(Result<MentionFeed, Error>)
    }

    private func performRefresh() async {
        repeat {
            needsRerun = false
            await fetchAll()
        } while needsRerun
        lastRefresh = now()
        isRefreshing = false
        inFlight = nil
    }

    private func fetchAll() async {
        let github = self.github
        let jira = self.jira
        await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .github(await Result { try await github.fetch() }) }
            group.addTask { .inProgress(await Result { try await jira.fetchInProgress() }) }
            group.addTask { .readyToRelease(await Result { try await jira.fetchReadyToRelease() }) }
            group.addTask { .mentions(await Result { try await jira.fetchMentions() }) }
            for await outcome in group {
                apply(outcome)
            }
        }
    }

    private func apply(_ outcome: Outcome) {
        switch outcome {
        case .github(.success(let result)):
            myPRs = SectionState(items: result.mine)
            reviewPRs = SectionState(items: result.review)
            recordPRs(result.mine)
        case .github(.failure(let error)):
            let message = Self.message(for: error)
            myPRs.error = message
            reviewPRs.error = message
        case .inProgress(.success(let issues)):
            inProgress = SectionState(items: issues)
        case .inProgress(.failure(let error)):
            inProgress.error = Self.message(for: error)
        case .readyToRelease(.success(let issues)):
            readyToRelease = SectionState(items: issues)
        case .readyToRelease(.failure(let error)):
            readyToRelease.error = Self.message(for: error)
        case .mentions(.success(let feed)):
            mentions = SectionState(items: feed.mentions)
            if feed.isComplete {
                let current = Set(feed.mentions.map(\.id))
                pruneSeen(keeping: current)
                pruneDismissed(keeping: current)
            }
        case .mentions(.failure(let error)):
            mentions.error = Self.message(for: error)
        }
    }

    private func recordPRs(_ prs: [PullRequest]) {
        let ids = Set(prs.map(\.id))
        var updated = prCommentSeen.filter { ids.contains($0.key) }
        for pr in prs where updated[pr.id] == nil {
            updated[pr.id] = pr.latestCommentAt ?? .distantPast
        }
        guard updated != prCommentSeen else { return }
        prCommentSeen = updated
        prSeenStore.save(updated)
    }

    private func pruneDismissed(keeping current: Set<String>) {
        let pruned = dismissedMentionIDs.intersection(current)
        guard pruned != dismissedMentionIDs else { return }
        dismissedMentionIDs = pruned
        dismissedStore.save(pruned)
    }

    private func pruneSeen(keeping current: Set<String>) {
        let pruned = seenMentionIDs.intersection(current)
        guard pruned != seenMentionIDs else { return }
        seenMentionIDs = pruned
        seenStore.save(pruned)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let error as GitHubError: return error.userMessage
        case let error as JiraError: return error.userMessage
        default: return error.localizedDescription
        }
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}
