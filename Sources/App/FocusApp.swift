import AppKit
import SwiftUI

@main
struct FocusApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(environment: environment, store: environment.store)
        } label: {
            MenuBarLabel(store: environment.store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: StatusStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.horizontal.fill")
            if store.badgeCount > 0 {
                Text(verbatim: String(store.badgeCount))
            }
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var hasToken: Bool
    @Published private(set) var saveError: String?
    let store: StatusStore

    private let keychain = Keychain()
    private var token: String?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init() {
        let config = ConfigStore.load(from: ConfigStore.defaultURL)
        let token = Keychain().read()
        self.config = config
        self.token = token
        self.hasToken = token != nil
        self.store = StatusStore(
            github: Self.makeGitHub(config),
            jira: Self.makeJira(config, token: token),
            seenStore: FileSeenStore(url: FileSeenStore.defaultURL),
            dismissedStore: FileSeenStore(url: FileSeenStore.dismissedURL),
            prSeenStore: FilePRSeenStore(url: FilePRSeenStore.defaultURL)
        )
        startTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.store.refresh()
            }
        }
        Task { await store.refresh() }
    }

    func apply(config newConfig: AppConfig, newToken: String?) {
        var errors: [String] = []
        do {
            try ConfigStore.save(newConfig, to: ConfigStore.defaultURL)
        } catch {
            errors.append("Could not save settings: \(error.localizedDescription)")
        }
        let trimmedToken = newToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedToken.isEmpty {
            token = trimmedToken
            do {
                try keychain.save(trimmedToken)
                hasToken = true
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        saveError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        config = newConfig
        store.reconfigure(github: Self.makeGitHub(newConfig), jira: Self.makeJira(newConfig, token: token))
        startTimer()
        Task { await store.refresh() }
    }

    func reviewInClaude(_ pr: PullRequest) {
        openInClaude(pr, prompt: config.reviewPrompt)
    }

    func addressCommentsInClaude(_ pr: PullRequest) {
        openInClaude(pr, prompt: config.commentsPrompt)
    }

    func prodRecheckInClaude(_ issues: [JiraIssue]) {
        open(message: ClaudeHandoff.releaseMessage(for: issues, prompt: config.releasePrompt), repository: config.releaseRepository)
    }

    private func openInClaude(_ pr: PullRequest, prompt: String) {
        open(message: ClaudeHandoff.message(for: pr, prompt: prompt), repository: pr.repoFullName)
    }

    private func open(message: String, repository: String) {
        let folder = RepoLocator.directoryURL(from: config.reposDirectory).flatMap { RepoLocator.localClone(of: repository, in: $0) }
        guard let url = ClaudeHandoff.url(message: message, folder: folder) else { return }
        NSWorkspace.shared.open(url)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: config.effectiveRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func makeGitHub(_ config: AppConfig) -> GitHubFetching {
        GitHubClient(
            ghPath: GhLocator.resolve(configured: config.ghPath),
            org: config.githubOrg,
            runner: ProcessRunner(),
            commentPolicy: CommentPolicy(botLogins: config.botAccounts, ignoredLogins: config.ignoredAccounts)
        )
    }

    private static func makeJira(_ config: AppConfig, token: String?) -> JiraFetching {
        JiraClient(config: config, token: token, transport: URLSessionTransport(), now: Date.init)
    }
}
