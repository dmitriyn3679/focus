import Foundation

await runGitHubParsingTests()
await runGitHubClientTests()
await runADFTests()
await runJiraParsingTests()
await runConfigTests()
await runJiraClientTests()
await runStatusStoreTests()
await runClaudeHandoffTests()

if failureCount == 0 {
    print("OK (\(testCount) tests)")
} else {
    print("FAILED (\(failureCount) failures in \(testCount) tests)")
}
exit(failureCount == 0 ? 0 : 1)
