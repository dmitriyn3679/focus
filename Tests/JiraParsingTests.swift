import Foundation

let jiraSite = "acme.atlassian.net"

func jiraComment(id: String, authorId: String, authorName: String = "Other Person", created: String, body: String?) -> String {
    #"{"id":"\#(id)","author":{"accountId":"\#(authorId)","displayName":"\#(authorName)"},"body":\#(body ?? "null"),"created":"\#(created)","updated":"\#(created)"}"#
}

func jiraComments(_ comments: String...) -> Data {
    Data(#"{"startAt":0,"maxResults":30,"total":\#(comments.count),"comments":[\#(comments.joined(separator: ","))]}"#.utf8)
}

let mentionIssue = JiraIssue(key: "WEB-3420", summary: "Recheck docs", status: "In progress", updatedAt: utc(2026, 11, 6), url: URL(string: "https://acme.atlassian.net/browse/WEB-3420")!)

func runJiraParsingTests() async {
    test("Jira parsing: dates") {
        expectEqual(JiraParsing.parseDate("2026-11-09T13:49:19.615+0000"), utc(2026, 11, 9, 13, 49, 19, 615))
        expectEqual(JiraParsing.parseDate("garbage"), nil)
    }

    test("Jira parsing: account id") {
        expectEqual(try JiraParsing.parseAccountId(Data(#"{"accountId":"712020:x","displayName":"D"}"#.utf8)), "712020:x")
        expectThrows { _ = try JiraParsing.parseAccountId(Data("{}".utf8)) }
    }

    test("Jira parsing: issues") {
        let json = #"{"issues":[{"key":"WEB-2744","fields":{"summary":"Invoice update","status":{"name":"In progress"},"updated":"2026-11-09T13:11:39.791+0000"}},{"key":"WEB-1","fields":{"summary":null}}]}"#
        let issues = try JiraParsing.parseIssues(Data(json.utf8), site: jiraSite)
        expectEqual(issues.count, 1)
        expectEqual(issues.first?.key, "WEB-2744")
        expectEqual(issues.first?.id, "WEB-2744")
        expectEqual(issues.first?.summary, "Invoice update")
        expectEqual(issues.first?.status, "In progress")
        expectEqual(issues.first?.updatedAt, utc(2026, 11, 9, 13, 11, 39, 791))
        expectEqual(issues.first?.url, URL(string: "https://acme.atlassian.net/browse/WEB-2744")!)
        expectEqual(try JiraParsing.parseIssues(Data(#"{"issues":[]}"#.utf8), site: jiraSite), [])
    }

    test("Jira parsing: mentions are filtered per comment") {
        let mentioning = adfDoc(adfParagraph(adfText("Waiting for recheck from "), adfMention(meAccountId)))
        let plain = adfDoc(adfParagraph(adfText("no mention here")))
        let data = jiraComments(
            jiraComment(id: "72415", authorId: "other", authorName: "Bob Tester", created: "2026-11-06T11:16:54.445+0000", body: mentioning),
            jiraComment(id: "72406", authorId: "other", created: "2026-11-06T10:24:06.282+0000", body: plain),
            jiraComment(id: "72012", authorId: "other", created: "2026-10-29T12:59:20.273+0000", body: mentioning),
            jiraComment(id: "72500", authorId: meAccountId, created: "2026-11-07T10:00:00.000+0000", body: mentioning),
            jiraComment(id: "72501", authorId: "other", created: "2026-11-07T11:00:00.000+0000", body: nil)
        )
        let mentions = try JiraParsing.parseMentions(data, issue: mentionIssue, accountId: meAccountId, since: utc(2026, 11, 2), site: jiraSite)
        expectEqual(mentions.count, 1)
        let mention = mentions.first
        expectEqual(mention?.id, "72415")
        expectEqual(mention?.issueKey, "WEB-3420")
        expectEqual(mention?.issueSummary, "Recheck docs")
        expectEqual(mention?.author, "Bob Tester")
        expectEqual(mention?.snippet, "Waiting for recheck from @Test User")
        expectEqual(mention?.createdAt, utc(2026, 11, 6, 11, 16, 54, 445))
        expectEqual(mention?.url, URL(string: "https://acme.atlassian.net/browse/WEB-3420?focusedCommentId=72415")!)
    }

    test("Jira parsing: long snippet is cut") {
        let long = String(repeating: "x", count: 300 - "@Test User ".count)
        let body = adfDoc(adfParagraph(adfMention(meAccountId), adfText(" " + long)))
        let data = jiraComments(jiraComment(id: "1", authorId: "other", created: "2026-11-06T11:16:54.445+0000", body: body))
        let mentions = try JiraParsing.parseMentions(data, issue: mentionIssue, accountId: meAccountId, since: utc(2026, 11, 2), site: jiraSite)
        expectEqual(mentions.first?.snippet.count, 141)
        expectEqual(mentions.first?.snippet.hasSuffix("…"), true)
    }

    test("Jira parsing: snippet collapses whitespace") {
        let body = adfDoc(adfParagraph(adfMention(meAccountId), adfText("  look\\n\\nhere  ")))
        let data = jiraComments(jiraComment(id: "1", authorId: "other", created: "2026-11-06T11:16:54.445+0000", body: body))
        let mentions = try JiraParsing.parseMentions(data, issue: mentionIssue, accountId: meAccountId, since: utc(2026, 11, 2), site: jiraSite)
        expectEqual(mentions.first?.snippet, "@Test User look here")
    }

    test("Jira parsing: in-progress JQL") {
        expectEqual(JiraParsing.inProgressJQL(statuses: ["In progress", "Code \"review\""]), #"assignee = currentUser() AND status in ("In progress", "Code \"review\"") ORDER BY updated DESC"#)
        expectEqual(JiraParsing.inProgressJQL(statuses: []), #"assignee = currentUser() AND status in ("In progress") ORDER BY updated DESC"#)
    }

    test("Jira parsing: ready-to-release JQL") {
        expectEqual(JiraParsing.releaseJQL(statuses: []), #"assignee = currentUser() AND status in ("Ready to release") ORDER BY updated DESC"#)
        expectEqual(JiraParsing.releaseJQL(statuses: ["Ready to release", " ", "Ready for prod"]), #"assignee = currentUser() AND status in ("Ready to release", "Ready for prod") ORDER BY updated DESC"#)
    }

    test("Jira parsing: mention candidates JQL") {
        expectEqual(JiraParsing.mentionCandidatesJQL(lookbackDays: 7), "comment ~ currentUser() AND updated >= -7d ORDER BY updated DESC")
    }
}
