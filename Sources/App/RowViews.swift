import AppKit
import SwiftUI

private struct DetailPart: Identifiable {
    let id: Int
    let text: String
    let color: Color
}

private struct DetailLine: View {
    let parts: [DetailPart]

    var body: some View {
        Text(attributed)
            .font(.caption)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for part in parts {
            if part.id > 0 {
                var separator = AttributedString(" · ")
                separator.foregroundColor = .secondary
                result += separator
            }
            var piece = AttributedString(part.text)
            piece.foregroundColor = part.color
            result += piece
        }
        return result
    }
}

private struct RowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func details(_ items: [(String, Color)]) -> [DetailPart] {
    items.enumerated().map { DetailPart(id: $0.offset, text: $0.element.0, color: $0.element.1) }
}

struct ClaudeAction {
    let systemImage: String
    let help: String
    let perform: () -> Void
}

struct PullRequestRow: View {
    let pr: PullRequest
    let showAuthor: Bool
    var newDot: Bool? = nil
    var onOpen: () -> Void = {}
    var claude: ClaudeAction? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
            if let claude {
                Button(action: claude.perform) {
                    Image(systemName: claude.systemImage)
                }
                .buttonStyle(IconButtonStyle())
                .help(claude.help)
            }
        }
    }

    private var content: some View {
        RowButton(action: {
            NSWorkspace.shared.open(pr.url)
            onOpen()
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let newDot {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .opacity(newDot ? 1 : 0)
                        .help(newDot ? "New comments since you last opened this PR" : "")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "#\(pr.number) \(pr.title)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showAuthor {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            DetailLine(parts: details(reviewDetails(now: context.date)))
                        }
                    } else {
                        DetailLine(parts: details(ownDetails))
                        if !pr.commentAuthors.isEmpty {
                            CommentAuthorsLine(counts: pr.commentCounts, authors: pr.commentAuthors)
                        }
                    }
                }
            }
        }
        .help("#\(pr.number) \(pr.title)")
    }

    private var ownDetails: [(String, Color)] {
        var items: [(String, Color)] = [(pr.repo, .secondary)]
        switch pr.reviewDecision {
        case .approved: items.append(("Approved", .green))
        case .changesRequested: items.append(("Changes requested", .red))
        case .reviewRequired: items.append(("Review required", .secondary))
        case nil: break
        }
        switch pr.checks {
        case .passed: items.append(("Checks passed", .green))
        case .failed: items.append(("Checks failed", .red))
        case .running: items.append(("Checks running", .secondary))
        case nil: break
        }
        if pr.unresolvedThreads > 0 {
            items.append(("\(pr.unresolvedThreads) unresolved", .secondary))
        }
        if pr.hasConflicts {
            items.append(("conflicts", .red))
        }
        return items
    }

    private func reviewDetails(now: Date) -> [(String, Color)] {
        var items: [(String, Color)] = []
        if let author = pr.author {
            items.append((author, .secondary))
        }
        items.append(("updated \(RelativeTime.string(for: pr.updatedAt, relativeTo: now))", .secondary))
        return items
    }
}

struct CommentAuthorsLine: View {
    let counts: CommentCounts
    let authors: [CommentAuthor]

    var body: some View {
        Text(verbatim: summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(authors.map { "\($0.isBot ? "🤖" : "👤") \($0.login) \($0.count)" }.joined(separator: "\n"))
    }

    private var summary: String {
        var parts: [String] = []
        if counts.people > 0 { parts.append("👤 \(counts.people)") }
        if counts.bots > 0 { parts.append("🤖 \(counts.bots)") }
        return parts.joined(separator: " · ")
    }
}

struct IssueRow: View {
    let issue: JiraIssue

    var body: some View {
        RowButton(action: { NSWorkspace.shared.open(issue.url) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(issue.key) \(issue.summary)")
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: issue.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(issue.url.absoluteString)
    }
}

struct MentionRow: View {
    let mention: Mention
    let isSeen: Bool
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
            Button(action: onDismiss) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(IconButtonStyle())
            .help("Hide this mention")
        }
    }

    private var content: some View {
        RowButton(action: {
            NSWorkspace.shared.open(mention.url)
            onOpen()
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .opacity(isSeen ? 0 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(verbatim: "\(mention.issueKey) · \(mention.author) · \(RelativeTime.string(for: mention.createdAt, relativeTo: context.date))")
                            .lineLimit(1)
                    }
                    Text(verbatim: mention.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .opacity(isSeen ? 0.5 : 1)
        }
        .help("\(mention.issueKey) \(mention.issueSummary)")
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .modifier(HoverHighlight(isPressed: configuration.isPressed))
    }
}

struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .modifier(HoverHighlight(isPressed: configuration.isPressed))
    }
}

private struct HoverHighlight: ViewModifier {
    let isPressed: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isPressed ? 0.2 : (isHovered ? 0.1 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering in
                guard hovering != isHovered else { return }
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovered {
                    isHovered = false
                    NSCursor.pop()
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
