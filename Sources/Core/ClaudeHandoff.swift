import Foundation

enum RepoLocator {
    static func directoryURL(from setting: String) -> URL? {
        let trimmed = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    static func localClone(of nameWithOwner: String, in directory: URL) -> URL? {
        let target = nameWithOwner.lowercased()
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        return entries
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first { entry in
                let config = entry.appendingPathComponent(".git/config")
                guard let text = try? String(contentsOf: config, encoding: .utf8) else { return false }
                return originRepo(inGitConfig: text) == target
            }
    }

    static func originRepo(inGitConfig text: String) -> String? {
        var inOrigin = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line == "[remote \"origin\"]"
                continue
            }
            guard inOrigin else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "url" else { continue }
            return repoName(fromRemote: parts[1])
        }
        return nil
    }

    private static func repoName(fromRemote remote: String) -> String? {
        guard let range = remote.range(of: "github.com", options: .caseInsensitive) else { return nil }
        var path = String(remote[range.upperBound...])
        while path.hasPrefix(":") || path.hasPrefix("/") {
            path.removeFirst()
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix(".git") {
            path.removeLast(4)
        }
        let components = path.split(separator: "/")
        guard components.count == 2 else { return nil }
        return path.lowercased()
    }
}

enum ClaudeHandoff {
    static let maxMessageLength = 5000

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func message(for pr: PullRequest, prompt: String) -> String {
        let link = String(pr.url.absoluteString.prefix(maxMessageLength))
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let room = maxMessageLength - link.count - 2
        guard !trimmedPrompt.isEmpty, room > 0 else { return link }
        return String(trimmedPrompt.prefix(room)) + "\n\n" + link
    }

    static let maxReleasePromptLength = 2500

    static func releaseMessage(for issues: [JiraIssue], prompt: String) -> String {
        let trimmedPrompt = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxReleasePromptLength))
        let header = trimmedPrompt.isEmpty ? "" : trimmedPrompt + "\n\n"
        let keys = issues.map(\.key)
        var included: [String] = []
        var used = header.count
        for (index, key) in keys.enumerated() {
            let remaining = keys.count - index - 1
            let overflow = remaining > 0 ? ", +\(remaining) more".count : 0
            let cost = (included.isEmpty ? 0 : 2) + key.count
            guard used + cost + overflow <= maxMessageLength else { break }
            included.append(key)
            used += cost
        }
        let omitted = keys.count - included.count
        if omitted > 0 {
            included.append("+\(omitted) more")
        }
        return header + included.joined(separator: ", ")
    }

    static func url(message: String, folder: URL?) -> URL? {
        var items = [("q", message)]
        if let folder {
            items.append(("folder", folder.path))
        }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/new"
        components.percentEncodedQuery = items
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
        return components.url
    }
}
