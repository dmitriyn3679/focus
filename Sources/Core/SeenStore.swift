import Foundation

protocol SeenStoring {
    func load() -> Set<String>
    func save(_ ids: Set<String>)
}

protocol PRSeenStoring {
    func load() -> [String: Date]
    func save(_ records: [String: Date])
}

struct FilePRSeenStore: PRSeenStoring {
    static var defaultURL: URL {
        ConfigStore.directoryURL.appendingPathComponent("seen-prs.json")
    }

    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() -> [String: Date] {
        guard
            let data = try? Data(contentsOf: url),
            let records = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return records
    }

    func save(_ records: [String: Date]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

struct FileSeenStore: SeenStoring {
    static var defaultURL: URL {
        ConfigStore.directoryURL.appendingPathComponent("seen-mentions.json")
    }

    static var dismissedURL: URL {
        ConfigStore.directoryURL.appendingPathComponent("dismissed-mentions.json")
    }

    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() -> Set<String> {
        guard
            let data = try? Data(contentsOf: url),
            let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    func save(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids.sorted()) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
