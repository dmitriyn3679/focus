import Foundation

struct ADFNode: Decodable {
    let type: String
    let text: String?
    let attrs: ADFAttrs?
    let content: [ADFNode]?

    private static let blockTypes: Set<String> = ["paragraph", "heading", "listItem", "tableCell", "blockquote", "codeBlock"]

    private enum CodingKeys: String, CodingKey {
        case type, text, attrs, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? ""
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        attrs = try? container.decodeIfPresent(ADFAttrs.self, forKey: .attrs)
        content = try? container.decodeIfPresent([ADFNode].self, forKey: .content)
    }

    func mentions(accountId: String) -> Bool {
        if type == "mention", attrs?.id == accountId {
            return true
        }
        return content?.contains { $0.mentions(accountId: accountId) } ?? false
    }

    var plainText: String {
        var segments: [String] = []
        var current = ""
        collect(into: &segments, current: &current)
        Self.flush(&current, into: &segments)
        return segments.joined(separator: " ")
    }

    private func collect(into segments: inout [String], current: inout String) {
        let isBlock = Self.blockTypes.contains(type)
        if isBlock {
            Self.flush(&current, into: &segments)
        }
        switch type {
        case "text":
            current += text ?? ""
        case "mention":
            current += attrs?.text ?? ""
        case "hardBreak":
            current += " "
        default:
            for child in content ?? [] {
                child.collect(into: &segments, current: &current)
            }
        }
        if isBlock {
            Self.flush(&current, into: &segments)
        }
    }

    private static func flush(_ current: inout String, into segments: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            segments.append(trimmed)
        }
        current = ""
    }
}

struct ADFAttrs: Decodable {
    let id: String?
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case id, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
    }
}
