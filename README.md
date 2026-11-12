# Focus

A small macOS menu bar app that shows, in one window, what needs your attention on GitHub and Jira, and hands a pull request or a release check to Claude Code in one click.

- **My PRs** — your open, non-draft pull requests, with review state, checks, unresolved threads and conflicts. A third line counts comments by people (👤) and bots (🤖) in unresolved review threads and the PR conversation; hover it for the names. A dot marks PRs with comments newer than the last time you opened the PR from Focus; those PRs add to the badge. While a PR has unresolved review threads, a wrench button opens a Claude Code session for it.
- **Review requests** — open pull requests where you are a requested reviewer. The ✨ button opens a Claude Code session for the PR.
- **In progress** — Jira issues assigned to you in progress.
- **Prod recheck** — a button in the **In progress** header, shown while you have Jira issues in Ready to release (the tooltip names them). It opens a Claude Code session with your prod recheck prompt and those issue keys.
- **Report** — a button next to it, shown once the Report prompt is filled. It opens a Claude Code session with that prompt, for example a daily report command.
- **Mentions** — Jira comments from the last days that @mention you. Unseen mentions have a dot; opening one marks it seen. The trash button hides a mention and **Clear all** hides the whole list; hidden mentions stay hidden in Focus (nothing changes in Jira), and new comments still appear.

The menu bar icon (a horizontal lightning bolt) shows a number: review requests plus unseen mentions plus your PRs with new comments. Data refreshes every 5 minutes, when the window opens (if the last refresh is older than a minute), after the Mac wakes, and on demand with the refresh button or ⌘R. The window footer shows the installed version.

## Install

1. Install the [GitHub CLI](https://cli.github.com) and log in: `brew install gh`, then `gh auth login` (scopes `repo`, `read:org`). Focus finds `gh` in `/opt/homebrew/bin` or `/usr/local/bin`.
2. Download `Focus.zip` from the latest release of this repository and unzip it.
3. Move `Focus.app` to `~/Applications` or `/Applications`.
4. The app is not notarized, so macOS blocks the first launch. Open it once, then go to System Settings → Privacy & Security and click **Open Anyway**. Or run `xattr -dr com.apple.quarantine /path/to/Focus.app` before opening it.
5. Click the bolt in the menu bar, then the gear, and fill in the settings (next section). Choose **Always Allow** when macOS asks about Keychain access.
6. To start Focus at login: System Settings → General → Login Items → add Focus.

To update, download the new release and replace `Focus.app`; your settings are kept.

## Setup: what to fill in

Everything starts empty. Open the gear in the Focus window.

### Environment tab

| Field | What to put | Example |
|---|---|---|
| GitHub → Organization | The GitHub organization whose pull requests you want to see. Leave empty to see pull requests from every organization. | `your-org` |
| GitHub → Repositories folder | The folder that holds your local clones. Focus finds the clone of a PR's repository here by its `origin` remote and opens the Claude Code session in it. Leave empty to open sessions without a folder. | `~/Projects` |
| GitHub → Bot accounts | GitHub logins of bots that review your code, comma-separated. Their comments are counted as 🤖. Accounts GitHub marks as bots are counted as bots anyway. | `review-bot` |
| GitHub → Ignored accounts | Logins whose comments should not be shown or counted at all, such as CI reports. | `github-actions, sonarqube` |
| GitHub → Prod recheck repository | The repository (`owner/name`) whose local clone **Prod recheck** and **Report** open. | `your-org/web` |
| Jira → Site | Your Jira Cloud host, without `https://`. Without it the Jira sections stay empty. | `your-company.atlassian.net` |
| Jira → Email | The email of your Atlassian account. | `you@your-company.com` |
| Jira → API token | A token from <https://id.atlassian.com/manage-profile/security/api-tokens> (also linked as **Create API token**). | |
| Refresh → Interval | Minutes between automatic refreshes. | `5` |

The token is stored only in the macOS Keychain and sent only to your Jira site. The stored token is never loaded into the field: it shows masked characters that are only a marker. Click the field to clear it and paste a new token; leaving it untouched keeps the stored token.

### Prompts tab

Each button opens a new Claude Code session in Claude Desktop, in your local clone of the repository, with the field's text first and then the data below. Nothing is sent until you press Enter.

| Field | Button | Sent after the text |
|---|---|---|
| Review requests | ✨ on a review request | the PR link |
| My PRs with comments | wrench on your PR with unresolved review threads | the PR link |
| Prod recheck | Prod recheck in the In progress header | the keys of your Ready to release issues, comma-separated |
| Report | Report in the In progress header (shown only while this field is filled) | nothing: the text is sent as is |

Put one of these in each field:

- **A plain prompt.** Works without any setup. Examples:
  - Review requests: `Review this pull request: read the diff against its base branch and list bugs, risks and missing tests with file:line references. Do not comment on GitHub.`
  - My PRs with comments: `Go through the unresolved review comments on this pull request. For each one, check it against the code and say whether it is valid, then propose a change or a reply. Do not edit files or reply on GitHub until I say so.`
  - Report: `Make a short report of the Jira issues I worked on today, grouped into Done and In progress, ready to paste into chat.`
  - Prod recheck: `For these Jira issues, find which translations, content blocks and SEO texts (title, description, h1, h2 and so on) they add or change, and check on production that each one is filled in every language. Report what is missing or empty, per issue and language.`
- **A slash command for your own skill.** A skill keeps a long, tuned instruction out of the field and can be improved over time. Ask Claude Code to create one, for example "create a skill prod-recheck in ~/.claude/skills that checks Jira issues' translations, content blocks and SEO texts on our production site", then put `/prod-recheck` in the field. Skills in `~/.claude/skills/` work in every repository; skills in a repository's `.claude/skills/` work only there. Focus sends the field as is, so the command must exist on your machine.

### Config file only

These are not in Settings. Change them in `~/.config/status-widget/config.json` if your Jira workflow uses other status names, then reopen Focus.

| Key | Default | Meaning |
|---|---|---|
| `inProgressStatuses` | `["In progress"]` | Statuses shown in **In progress** |
| `releaseStatuses` | `["Ready to release"]` | Statuses whose issues **Prod recheck** sends |
| `mentionsLookbackDays` | `7` | How far back mentions are collected |
| `ghPath` | `/opt/homebrew/bin/gh` | Preferred path to `gh`; Focus falls back to `/opt/homebrew/bin/gh` and `/usr/local/bin/gh` |

## Requirements

- macOS 14 or later, Apple silicon or Intel (the app is a universal binary).
- GitHub CLI logged in, with `repo` and `read:org` scopes.
- A Jira Cloud account and an API token for the Jira sections.
- Claude Desktop with Claude Code for the ✨, wrench and Prod recheck buttons.
- To build from source: Command Line Tools (`xcode-select --install`). Full Xcode and SwiftPM are not needed.

## Build from source

```bash
scripts/test.sh
```

Compiles the core sources with the tests into `build/tests` and runs them. Prints `OK (<n> tests)` and exits 0 on success, or one `FAIL <file>:<line> <message>` line per failure and exits 1.

```bash
scripts/build.sh
```

Compiles a universal (arm64 + x86_64) binary with `swiftc` and produces an ad-hoc signed `build/app.noindex/Focus.app` (the `.noindex` folder keeps the build copy out of Spotlight and Launchpad).

```bash
scripts/install.sh
```

Builds, quits a running copy, installs to `~/Applications/Focus.app` and opens it. `--login` also adds `~/Library/LaunchAgents/local.focus.plist` so the app starts at login; `--uninstall` removes the login item and the installed app and keeps settings and the Keychain item.

```bash
scripts/package.sh
```

Builds and zips the app with this README into `build/Focus.zip`.

```bash
scripts/make-icon.sh
```

Redraws the app icon (drawn in `scripts/icon/MakeIcon.swift`) into `Resources/AppIcon.icns`. Only needed after changing the drawing.

## Releasing a new version

1. Raise `CFBundleShortVersionString` (for example `1.1.0`) and `CFBundleVersion` (a whole number, +1) in `Resources/Info.plist`.
2. Run `scripts/test.sh` and `scripts/package.sh`.
3. Commit, then publish the release: `gh release create v1.1.0 build/Focus.zip --title "Focus 1.1.0" --notes "What changed"`.

## Stored data

- `~/.config/status-widget/config.json` — settings, never the token.
- `~/.config/status-widget/seen-mentions.json` — ids of mentions you have opened or marked seen.
- `~/.config/status-widget/dismissed-mentions.json` — ids of mentions you have hidden.
- `~/.config/status-widget/seen-prs.json` — for each of your PRs, the time of the newest comment you have seen.
- Keychain generic password, service `status-widget`, account `jira-api-token`.

## Claude Code handoff

The buttons open `claude://code/new?folder=<clone>&q=<message>` (message up to 5,000 characters). The prompt is typed into the first message, not set as a system prompt, and is not sent until you press Enter. The `folder` parameter is what Claude Desktop's own Finder service uses; it is not in the public documentation and may change.
