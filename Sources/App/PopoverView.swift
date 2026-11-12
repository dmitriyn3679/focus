import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var store: StatusStore
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                SettingsView(environment: environment) { showingSettings = false }
            } else {
                header
                Divider()
                sections
                Divider()
                footer
            }
        }
        .frame(width: 380)
        .onAppear { refreshIfStale() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshIfStale()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Focus").font(.headline)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(verbatim: lastRefreshText(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small).frame(width: 24, height: 24)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh (⌘R)")
            }
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var sections: some View {
        CappedScrollView(maxHeight: 520) {
            VStack(alignment: .leading, spacing: 14) {
                SectionView(title: "My PRs", state: store.myPRs) { pr in
                    PullRequestRow(
                        pr: pr,
                        showAuthor: false,
                        newDot: store.hasNewComments(pr),
                        onOpen: { store.markPRSeen(pr) },
                        claude: pr.needsAttention ? ClaudeAction(systemImage: "wrench.adjustable", help: "Fix review comments in Claude Code") {
                            store.markPRSeen(pr)
                            environment.addressCommentsInClaude(pr)
                        } : nil
                    )
                }
                SectionView(title: "Review requests", state: store.reviewPRs) { pr in
                    PullRequestRow(
                        pr: pr,
                        showAuthor: true,
                        claude: ClaudeAction(systemImage: "sparkles", help: "Review in Claude Code") {
                            environment.reviewInClaude(pr)
                        }
                    )
                }
                SectionView(title: "In progress", state: store.inProgress, accessory: {
                    HStack(spacing: 2) {
                        if !store.readyToRelease.items.isEmpty {
                            Button {
                                environment.prodRecheckInClaude(store.readyToRelease.items)
                            } label: {
                                Label("Prod recheck", systemImage: "sparkles")
                            }
                            .buttonStyle(TextButtonStyle())
                            .help(prodRecheckHelp)
                        }
                        if !reportPrompt.isEmpty {
                            Button {
                                environment.reportInClaude()
                            } label: {
                                Label("Report", systemImage: "doc.text")
                            }
                            .buttonStyle(TextButtonStyle())
                            .help("Open a Claude Code session with: \(reportPrompt)")
                        }
                    }
                }) { issue in
                    IssueRow(issue: issue)
                }
                SectionView(title: "Mentions", state: store.visibleMentions, accessory: {
                    HStack(spacing: 2) {
                        if store.unseenMentionCount > 0 {
                            Button("Mark all seen") { store.markAllSeen() }
                                .buttonStyle(TextButtonStyle())
                        }
                        if !store.visibleMentions.items.isEmpty {
                            Button("Clear all") { store.dismissAllMentions() }
                                .buttonStyle(TextButtonStyle())
                                .help("Hide every mention in this list")
                        }
                    }
                }) { mention in
                    MentionRow(
                        mention: mention,
                        isSeen: store.seenMentionIDs.contains(mention.id),
                        onOpen: { store.markSeen(mention.id) },
                        onDismiss: { store.dismissMention(mention.id) }
                    )
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack {
            Text(verbatim: Self.versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Focus version")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var reportPrompt: String {
        environment.config.reportPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var prodRecheckHelp: String {
        let issues = store.readyToRelease.items
        let keys = issues.map(\.key).joined(separator: ", ")
        return "Check i18n keys and content blocks on production for \(issues.count) Ready to release issue\(issues.count == 1 ? "" : "s"): \(keys)"
    }

    private static let versionText: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "v\(version) (\($0))" } ?? "v\(version)"
    }()

    private func lastRefreshText(now: Date) -> String {
        guard let lastRefresh = store.lastRefresh else { return "Never" }
        return RelativeTime.string(for: lastRefresh, relativeTo: now)
    }

    private func refreshIfStale() {
        Task { await store.refreshIfStale(olderThan: 60) }
    }
}

struct CappedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SectionView<Item: Equatable & Identifiable, Row: View, Accessory: View>: View {
    let title: String
    let state: SectionState<Item>
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let row: (Item) -> Row

    init(title: String, state: SectionState<Item>, @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder row: @escaping (Item) -> Row) {
        self.title = title
        self.state = state
        self.accessory = accessory
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(verbatim: String(state.items.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                accessory()
            }
            if let error = state.error {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(error)
            }
            if state.items.isEmpty {
                Text("Nothing here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.items) { item in
                    row(item)
                }
            }
        }
    }
}

extension SectionView where Accessory == EmptyView {
    init(title: String, state: SectionState<Item>, @ViewBuilder row: @escaping (Item) -> Row) {
        self.init(title: title, state: state, accessory: { EmptyView() }, row: row)
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func string(for date: Date, relativeTo now: Date) -> String {
        if now.timeIntervalSince(date) < 60 {
            return "just now"
        }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
