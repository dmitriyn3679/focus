import Foundation

let gitHubFixture = """
{"data":{
  "mine":{"nodes":[
    {"number":1944,"title":"WEB-3342 Add rental period discounts to the order form","url":"https://github.com/acme/web/pull/1944","updatedAt":"2026-11-09T15:38:46Z","reviewDecision":"REVIEW_REQUIRED","mergeable":"MERGEABLE","author":{"login":"me-dev"},"repository":{"nameWithOwner":"acme/web"},"reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":true},{"isResolved":false}]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]}},
    {"number":7,"title":"bare","url":"https://github.com/acme/x/pull/7","updatedAt":"2026-11-01T00:00:00Z","reviewDecision":null,"mergeable":"CONFLICTING","author":null,"repository":{"nameWithOwner":"acme/x"},"reviewThreads":{"nodes":[]},"commits":{"nodes":[]}},
    {}
  ]},
  "review":{"nodes":[
    {"number":1521,"title":"WEB-2858 Update dashboard button logic","url":"https://github.com/acme/web/pull/1521","updatedAt":"2026-07-17T09:22:31Z","reviewDecision":"APPROVED","mergeable":"UNKNOWN","author":{"login":"alice"},"repository":{"nameWithOwner":"acme/web"},"reviewThreads":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}
  ]}
}}
"""

private func checksFixture(_ state: String) -> String {
    """
    {"data":{"mine":{"nodes":[{"number":1,"title":"t","url":"https://github.com/o/r/pull/1","updatedAt":"2026-01-01T00:00:00Z","mergeable":"MERGEABLE","repository":{"nameWithOwner":"o/r"},"reviewThreads":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"\(state)"}}}]}}]},"review":{"nodes":[]}}}
    """
}

let commentsFixture = """
{"data":{"viewer":{"login":"me-dev"},
  "mine":{"nodes":[
    {"number":1950,"title":"Fix invoice export","url":"https://github.com/acme/web/pull/1950","updatedAt":"2026-11-10T09:00:00Z","reviewDecision":"CHANGES_REQUESTED","mergeable":"MERGEABLE","author":{"login":"me-dev"},"repository":{"nameWithOwner":"acme/web"},
     "comments":{"nodes":[
       {"author":{"__typename":"Bot","login":"github-actions"},"createdAt":"2026-11-10T10:00:00Z"},
       {"author":{"__typename":"User","login":"alice"},"createdAt":"2026-11-10T11:00:00Z"},
       {"author":{"__typename":"User","login":"me-dev"},"createdAt":"2026-11-10T12:00:00Z"},
       {"author":null,"createdAt":"2026-11-10T12:30:00Z"}
     ]},
     "reviewThreads":{"nodes":[
       {"isResolved":false,"comments":{"nodes":[
         {"author":{"__typename":"User","login":"Review-Bot"},"createdAt":"2026-11-10T10:30:00Z"},
         {"author":{"__typename":"User","login":"me-dev"},"createdAt":"2026-11-10T10:40:00Z"},
         {"author":{"__typename":"User","login":"review-bot"},"createdAt":"2026-11-10T10:50:00Z"}
       ]}},
       {"isResolved":true,"comments":{"nodes":[{"author":{"__typename":"User","login":"alice"},"createdAt":"2026-11-10T09:00:00Z"}]}},
       {"isResolved":false,"comments":{"nodes":[{"author":{"__typename":"Bot","login":"some-app"},"createdAt":"2026-11-10T13:00:00Z"}]}}
     ]},
     "commits":{"nodes":[]}}
  ]},
  "review":{"nodes":[]}
}}
"""

let commentPolicy = CommentPolicy(botLogins: ["Review-Bot"], ignoredLogins: ["github-actions", "sonarqube"])

func runGitHubParsingTests() async {
    test("GitHub parsing: counted comments skip self, ignored, resolved and authorless") {
        let pr = try GitHubParsing.parse(Data(commentsFixture.utf8), policy: commentPolicy).mine[0]
        expectEqual(pr.comments, [
            PRComment(author: "alice", isBot: false, createdAt: utc(2026, 11, 10, 11)),
            PRComment(author: "Review-Bot", isBot: true, createdAt: utc(2026, 11, 10, 10, 30)),
            PRComment(author: "review-bot", isBot: true, createdAt: utc(2026, 11, 10, 10, 50)),
            PRComment(author: "some-app", isBot: true, createdAt: utc(2026, 11, 10, 13)),
        ])
        expectEqual(pr.unresolvedThreads, 2)
        expectEqual(pr.latestCommentAt, utc(2026, 11, 10, 13))
    }

    test("GitHub parsing: comment authors group people first, then bots") {
        let pr = try GitHubParsing.parse(Data(commentsFixture.utf8), policy: commentPolicy).mine[0]
        expectEqual(pr.commentAuthors, [
            CommentAuthor(login: "alice", isBot: false, count: 1),
            CommentAuthor(login: "Review-Bot", isBot: true, count: 2),
            CommentAuthor(login: "some-app", isBot: true, count: 1),
        ])
    }

    test("GitHub parsing: comment counts by people and bots") {
        let pr = try GitHubParsing.parse(Data(commentsFixture.utf8), policy: commentPolicy).mine[0]
        expectEqual(pr.commentCounts, CommentCounts(people: 1, bots: 3))
        expectEqual(try GitHubParsing.parse(Data(gitHubFixture.utf8)).mine[0].commentCounts, CommentCounts(people: 0, bots: 0))
    }

    test("GitHub parsing: PR without comment data has no comments") {
        let pr = try GitHubParsing.parse(Data(gitHubFixture.utf8)).mine[0]
        expectEqual(pr.comments, [])
        expectEqual(pr.commentAuthors, [])
        expectEqual(pr.latestCommentAt, nil)
    }

    test("GitHub parsing: counts skip empty nodes") {
        let result = try GitHubParsing.parse(Data(gitHubFixture.utf8))
        expectEqual(result.mine.count, 2)
        expectEqual(result.review.count, 1)
    }

    test("GitHub parsing: full PR fields") {
        let pr = try GitHubParsing.parse(Data(gitHubFixture.utf8)).mine[0]
        expectEqual(pr.number, 1944)
        expectEqual(pr.title, "WEB-3342 Add rental period discounts to the order form")
        expectEqual(pr.url, URL(string: "https://github.com/acme/web/pull/1944")!)
        expectEqual(pr.id, "https://github.com/acme/web/pull/1944")
        expectEqual(pr.repo, "web")
        expectEqual(pr.repoFullName, "acme/web")
        expectEqual(pr.author, "me-dev")
        expectEqual(pr.reviewDecision, .reviewRequired)
        expectEqual(pr.checks, .running)
        expectEqual(pr.unresolvedThreads, 2)
        expectEqual(pr.hasConflicts, false)
        expectEqual(pr.updatedAt, utc(2026, 11, 9, 15, 38, 46))
    }

    test("GitHub parsing: absent optional fields") {
        let pr = try GitHubParsing.parse(Data(gitHubFixture.utf8)).mine[1]
        expectEqual(pr.reviewDecision, nil)
        expectEqual(pr.checks, nil)
        expectEqual(pr.author, nil)
        expectEqual(pr.unresolvedThreads, 0)
        expectEqual(pr.hasConflicts, true)
    }

    test("GitHub parsing: review request with null rollup") {
        let pr = try GitHubParsing.parse(Data(gitHubFixture.utf8)).review[0]
        expectEqual(pr.reviewDecision, .approved)
        expectEqual(pr.checks, nil)
        expectEqual(pr.author, "alice")
    }

    test("GitHub parsing: checks states") {
        let cases: [(String, ChecksState)] = [("SUCCESS", .passed), ("FAILURE", .failed), ("ERROR", .failed), ("PENDING", .running), ("EXPECTED", .running)]
        for (state, expected) in cases {
            let result = try GitHubParsing.parse(Data(checksFixture(state).utf8))
            expectEqual(result.mine.first?.checks, expected)
        }
    }

    test("GitHub parsing: invalid JSON throws") {
        expectThrows { _ = try GitHubParsing.parse(Data("not json".utf8)) }
    }

    test("GitHub parsing: GraphQL errors throw failed") {
        expectError(GitHubError.failed("Bad credentials")) {
            _ = try GitHubParsing.parse(Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8))
        }
    }
}
