import Foundation

private func withTempConfigURL(_ body: (URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("status-widget-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appendingPathComponent("nested/config.json"))
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func runConfigTests() async {
    test("Config: defaults") {
        let config = AppConfig.default
        expectEqual(config.githubOrg, "")
        expectEqual(config.ghPath, "/opt/homebrew/bin/gh")
        expectEqual(config.jiraSite, "")
        expectEqual(config.jiraEmail, "")
        expectEqual(config.inProgressStatuses, ["In progress"])
        expectEqual(config.mentionsLookbackDays, 7)
        expectEqual(config.refreshIntervalSeconds, 300)
        expectEqual(config.reviewPrompt, "")
        expectEqual(config.commentsPrompt, "")
        expectEqual(config.reposDirectory, "")
        expectEqual(config.releaseStatuses, ["Ready to release"])
        expectEqual(config.releaseRepository, "")
        expectEqual(config.releasePrompt, "")
        expectEqual(config.botAccounts, [])
        expectEqual(config.ignoredAccounts, ["github-actions"])
    }

    test("Config: missing file loads defaults") {
        withTempConfigURL { url in
            expectEqual(ConfigStore.load(from: url), .default)
        }
    }

    test("Config: partial file keeps other defaults") {
        try withTempConfigURL { url in
            try write(#"{"githubOrg":"acme"}"#, to: url)
            var expected = AppConfig.default
            expected.githubOrg = "acme"
            expectEqual(ConfigStore.load(from: url), expected)
        }
    }

    test("Config: invalid file loads defaults and is left alone") {
        try withTempConfigURL { url in
            try write("not json", to: url)
            expectEqual(ConfigStore.load(from: url), .default)
            expectEqual(try String(contentsOf: url, encoding: .utf8), "not json")
        }
    }

    test("Config: save and load round-trip") {
        try withTempConfigURL { url in
            var config = AppConfig.default
            config.githubOrg = "acme"
            config.ghPath = "/usr/local/bin/gh"
            config.jiraSite = "acme.atlassian.net"
            config.jiraEmail = "me@example.com"
            config.inProgressStatuses = ["In progress", "Code review"]
            config.mentionsLookbackDays = 14
            config.refreshIntervalSeconds = 600
            config.reviewPrompt = "Review it\nCarefully"
            config.commentsPrompt = "Fix the comments"
            config.releaseStatuses = ["Ready for prod"]
            config.releaseRepository = "acme/site"
            config.releasePrompt = "Check prod"
            config.botAccounts = ["robot"]
            config.ignoredAccounts = []
            config.reposDirectory = "/tmp/repos"
            try ConfigStore.save(config, to: url)
            expectEqual(ConfigStore.load(from: url), config)
        }
    }

    test("Config: effective refresh interval has a floor") {
        var config = AppConfig.default
        config.refreshIntervalSeconds = 5
        expectEqual(config.effectiveRefreshInterval, 60)
        config.refreshIntervalSeconds = 600
        expectEqual(config.effectiveRefreshInterval, 600)
    }

    test("Config: saved JSON has no token key") {
        try withTempConfigURL { url in
            var config = AppConfig.default
            config.jiraEmail = "me@example.com"
            try ConfigStore.save(config, to: url)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let keys = object.map { Array($0.keys) } ?? []
            expect(!keys.isEmpty, "no keys saved")
            expect(keys.allSatisfy { !$0.lowercased().contains("token") }, "keys: \(keys)")
        }
    }

    test("Config: default URL") {
        expectEqual(ConfigStore.defaultURL.path, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/status-widget/config.json").path)
    }
}
