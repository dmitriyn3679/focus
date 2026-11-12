import Foundation

struct AppConfig: Codable, Equatable {
    var githubOrg: String
    var ghPath: String
    var jiraSite: String
    var jiraEmail: String
    var inProgressStatuses: [String]
    var mentionsLookbackDays: Int
    var refreshIntervalSeconds: Int
    var reviewPrompt: String
    var commentsPrompt: String
    var reposDirectory: String
    var releaseStatuses: [String]
    var releaseRepository: String
    var releasePrompt: String
    var botAccounts: [String]
    var ignoredAccounts: [String]

    static let defaultReleasePrompt = ""

    static let `default` = AppConfig(
        githubOrg: "",
        ghPath: "/opt/homebrew/bin/gh",
        jiraSite: "",
        jiraEmail: "",
        inProgressStatuses: ["In progress"],
        mentionsLookbackDays: 7,
        refreshIntervalSeconds: 300,
        reviewPrompt: "",
        commentsPrompt: "",
        reposDirectory: "",
        releaseStatuses: ["Ready to release"],
        releaseRepository: "",
        releasePrompt: defaultReleasePrompt,
        botAccounts: [],
        ignoredAccounts: ["github-actions"]
    )

    var effectiveRefreshInterval: TimeInterval {
        TimeInterval(max(60, refreshIntervalSeconds))
    }

    init(githubOrg: String, ghPath: String, jiraSite: String, jiraEmail: String, inProgressStatuses: [String], mentionsLookbackDays: Int, refreshIntervalSeconds: Int, reviewPrompt: String, commentsPrompt: String, reposDirectory: String, releaseStatuses: [String], releaseRepository: String, releasePrompt: String, botAccounts: [String], ignoredAccounts: [String]) {
        self.githubOrg = githubOrg
        self.ghPath = ghPath
        self.jiraSite = jiraSite
        self.jiraEmail = jiraEmail
        self.inProgressStatuses = inProgressStatuses
        self.mentionsLookbackDays = mentionsLookbackDays
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.reviewPrompt = reviewPrompt
        self.commentsPrompt = commentsPrompt
        self.reposDirectory = reposDirectory
        self.releaseStatuses = releaseStatuses
        self.releaseRepository = releaseRepository
        self.releasePrompt = releasePrompt
        self.botAccounts = botAccounts
        self.ignoredAccounts = ignoredAccounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppConfig.default
        githubOrg = try container.decodeIfPresent(String.self, forKey: .githubOrg) ?? fallback.githubOrg
        ghPath = try container.decodeIfPresent(String.self, forKey: .ghPath) ?? fallback.ghPath
        jiraSite = try container.decodeIfPresent(String.self, forKey: .jiraSite) ?? fallback.jiraSite
        jiraEmail = try container.decodeIfPresent(String.self, forKey: .jiraEmail) ?? fallback.jiraEmail
        inProgressStatuses = try container.decodeIfPresent([String].self, forKey: .inProgressStatuses) ?? fallback.inProgressStatuses
        mentionsLookbackDays = try container.decodeIfPresent(Int.self, forKey: .mentionsLookbackDays) ?? fallback.mentionsLookbackDays
        refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? fallback.refreshIntervalSeconds
        reviewPrompt = try container.decodeIfPresent(String.self, forKey: .reviewPrompt) ?? fallback.reviewPrompt
        commentsPrompt = try container.decodeIfPresent(String.self, forKey: .commentsPrompt) ?? fallback.commentsPrompt
        reposDirectory = try container.decodeIfPresent(String.self, forKey: .reposDirectory) ?? fallback.reposDirectory
        releaseStatuses = try container.decodeIfPresent([String].self, forKey: .releaseStatuses) ?? fallback.releaseStatuses
        releaseRepository = try container.decodeIfPresent(String.self, forKey: .releaseRepository) ?? fallback.releaseRepository
        releasePrompt = try container.decodeIfPresent(String.self, forKey: .releasePrompt) ?? fallback.releasePrompt
        botAccounts = try container.decodeIfPresent([String].self, forKey: .botAccounts) ?? fallback.botAccounts
        ignoredAccounts = try container.decodeIfPresent([String].self, forKey: .ignoredAccounts) ?? fallback.ignoredAccounts
    }
}

enum ConfigStore {
    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/status-widget", isDirectory: true)
    }

    static var defaultURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }

    static func load(from url: URL) -> AppConfig {
        guard
            let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return .default }
        return config
    }

    static func save(_ config: AppConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
