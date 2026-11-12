import SwiftUI

struct SettingsView: View {
    @ObservedObject var environment: AppEnvironment
    let onClose: () -> Void

    @State private var githubOrg: String
    @State private var jiraSite: String
    @State private var jiraEmail: String
    @State private var token: String
    @FocusState private var tokenFocused: Bool
    @State private var intervalMinutes: Int
    @State private var reviewPrompt: String
    @State private var commentsPrompt: String
    @State private var reposDirectory: String
    @State private var releaseRepository: String
    @State private var releasePrompt: String
    @State private var botAccounts: String
    @State private var ignoredAccounts: String

    private static let maskedToken = String(repeating: "\u{2022}", count: 16)
    private static let tokenURL = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!

    init(environment: AppEnvironment, onClose: @escaping () -> Void) {
        self.environment = environment
        self.onClose = onClose
        let config = environment.config
        _githubOrg = State(initialValue: config.githubOrg)
        _token = State(initialValue: environment.hasToken ? Self.maskedToken : "")
        _jiraSite = State(initialValue: config.jiraSite)
        _jiraEmail = State(initialValue: config.jiraEmail)
        _intervalMinutes = State(initialValue: max(1, config.refreshIntervalSeconds / 60))
        _reviewPrompt = State(initialValue: config.reviewPrompt)
        _commentsPrompt = State(initialValue: config.commentsPrompt)
        _reposDirectory = State(initialValue: config.reposDirectory)
        _releaseRepository = State(initialValue: config.releaseRepository)
        _releasePrompt = State(initialValue: config.releasePrompt)
        _botAccounts = State(initialValue: config.botAccounts.joined(separator: ", "))
        _ignoredAccounts = State(initialValue: config.ignoredAccounts.joined(separator: ", "))
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case environment = "Environment"
        case prompts = "Prompts"

        var id: Self { self }
    }

    @State private var tab: Tab = .environment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            CappedScrollView(maxHeight: 520) {
                Group {
                    switch tab {
                    case .environment: environmentTab
                    case .prompts: promptsTab
                    }
                }
                .padding(.trailing, 4)
            }
            if let error = environment.saveError {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
    }

    private var environmentTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("GitHub") {
                field("Organization") {
                    TextField("your-org (empty: all organizations)", text: $githubOrg)
                }
                field("Repositories folder") {
                    TextField("~/Projects", text: $reposDirectory)
                    hint("Local clones are found here by their origin remote for Claude Code sessions.")
                }
                field("Bot accounts") {
                    TextField("review-bot, another-bot", text: $botAccounts)
                    hint("Comments from these logins are shown with 🤖.")
                }
                field("Ignored accounts") {
                    TextField("github-actions", text: $ignoredAccounts)
                    hint("Comments from these logins are not shown or counted.")
                }
                field("Prod recheck repository") {
                    TextField("owner/repo", text: $releaseRepository)
                }
            }
            group("Jira") {
                field("Site") {
                    TextField("your-company.atlassian.net", text: $jiraSite)
                }
                field("Email") {
                    TextField("you@example.com", text: $jiraEmail)
                }
                field("API token") {
                    SecureField("API token", text: $token, prompt: Text("Paste token"))
                        .focused($tokenFocused)
                        .onChange(of: tokenFocused) { _, focused in
                            if focused, token == Self.maskedToken {
                                token = ""
                            } else if !focused, token.isEmpty, environment.hasToken {
                                token = Self.maskedToken
                            }
                        }
                    Link("Create API token", destination: Self.tokenURL)
                        .font(.caption)
                }
            }
            group("Refresh") {
                field("Interval, minutes") {
                    HStack {
                        TextField("5", value: $intervalMinutes, format: .number)
                            .frame(width: 60)
                        Stepper("", value: $intervalMinutes, in: 1...240)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private var promptsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            promptField("Review requests", text: $reviewPrompt, hint: "Sent above the PR link when you press ✨ on a review request.")
            promptField("My PRs with comments", text: $commentsPrompt, hint: "Sent above the PR link when you press the wrench on your PR with unresolved review threads.")
            promptField("Prod recheck", text: $releasePrompt, hint: "Sent above the keys of your Ready to release issues when you press Prod recheck.")
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func promptField(_ label: String, text: Binding<String>, hint: String) -> some View {
        field(label) {
            TextEditor(text: text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 100)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            self.hint(hint)
        }
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        var config = environment.config
        config.githubOrg = githubOrg.trimmingCharacters(in: .whitespacesAndNewlines)
        config.jiraSite = jiraSite.trimmingCharacters(in: .whitespacesAndNewlines)
        config.jiraEmail = jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        config.refreshIntervalSeconds = max(1, intervalMinutes) * 60
        config.reviewPrompt = reviewPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        config.commentsPrompt = commentsPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        config.reposDirectory = reposDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        config.releaseRepository = releaseRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        config.releasePrompt = releasePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        config.botAccounts = Self.list(botAccounts)
        config.ignoredAccounts = Self.list(ignoredAccounts)
        environment.apply(config: config, newToken: token == Self.maskedToken ? nil : token)
        token = environment.hasToken ? Self.maskedToken : ""
        if environment.saveError == nil {
            onClose()
        }
    }
}
