# Security

This document describes what Tokenometer touches on your Mac, which credentials it reads, how it uses them, and what it sends over the network. It is written so you can verify each claim against the source.

## Summary

- Tokenometer runs unsandboxed, with the hardened runtime, Developer ID signed and notarized. Unsandboxed is what lets it read other tools' log directories.
- It never reads your Claude login. Claude's usage percent arrives through usage-reporter, a separate Claude Code mod, where Claude Code makes the request with its own credential.
- It reads no provider login at all: not Claude's, not Google's, not OpenAI's. The one secret it handles is the CSRF token of the Antigravity process already running on your Mac, used for a localhost call.
- Tokenometer sends nothing to any provider. Its only network traffic is a localhost call to Antigravity and the update check. There is no server of ours.
- There is no telemetry, analytics, or crash reporting. See [PRIVACY.md](PRIVACY.md).

## Credentials

### Claude Code login (Anthropic)

Not read. Tokenometer does not open the `Claude Code-credentials` keychain item or `~/.claude/.credentials.json`, and makes no request to Anthropic.

Usage percent comes from [usage-reporter](https://github.com/tksunw/usage-reporter), a separate Claude Code mod that you install into Claude Code yourself. Tokenometer only reads the file it writes. What the mod does, for reference:

- **What it does**: on session start and when Claude Code reports that a rate-limit window moved, it asks Claude Code to `GET https://api.anthropic.com/api/oauth/usage`, the call behind `claude /usage`, and writes the windows to `~/.claude/usage-reporter/usage.json`. At most one call per five minutes across all sessions, ten minutes after a 429.
- **The credential**: the mod calls `$.session.authorize()`, which gives it an opaque handle, and passes the handle to `$.http.fetch`. Claude Code attaches the credential on its side; the token never reaches the mod, the file, or Tokenometer.
- **Between calls, and if a call fails**: the mod writes the 5-hour and 7-day percentages Claude Code already holds for its status line, over the last full response. No request is made for those.
- **What the file holds**: percentages, reset times, credit figures, Anthropic's per-surface breakdown, and `raw`, Anthropic's last response as given. No token, no prompts. Tokenometer reads only the percentages, reset times, and breakdown.
- **Source**: `hooks/register.ts` in the usage-reporter repository; the file is read by `TokenometerCore/Sources/TokenometerCore/Network/ClaudeUsageFile.swift`.

### Gemini CLI login (Google)

Not read. Tokenometer does not open `~/.gemini/oauth_creds.json` and makes no request to Google. An earlier version called Google's Code Assist quota endpoint with that login for licensed Workspace accounts; that was removed (ADR-0005).

### Antigravity language server (Google)

- **What**: the CSRF token on the command line of Antigravity's running `language_server` process (`--csrf_token <value>`), and that process's listening localhost ports. Tokenometer finds both with `ps` and `lsof`, without privileges. `ps` lists every account's processes, so only those running as you are used; another user on the Mac cannot stand in a look-alike.
- **How it is used**: `POST http://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` and `GetUserStatus` with the CSRF header. These are the same local RPCs the Antigravity IDE and the `agy` CLI use to draw their quota bars. The calls bypass any system proxy and do not follow redirects, so nothing leaves the machine; the language server itself talks to Google with its own credentials, exactly as it would without Tokenometer. Source: `AntigravityLocalClient.swift`.
- Tokenometer does not read Antigravity's own OAuth token in the keychain.

### Codex

No credentials. Codex writes its rate limits into its own session logs, which are read like any other log.

## Files read

All read-only, all under your home directory:

- `~/.claude/projects/**/*.jsonl`, `~/.claude.json` (for the `oauthAccount` block that says whether a login exists and which plan), `~/.claude/usage-reporter/usage.json` (written by the usage-reporter mod)
- `~/Library/Application Support/Claude/local-agent-mode-sessions/**/*.jsonl`
- `~/.codex/sessions/**/*.jsonl`
- `~/.gemini/tmp/**/chats/session-*.jsonl` and `.json`, `~/.gemini/settings.json` (auth type)
- `~/.gemini/antigravity/conversations/*.db` with their `-wal` and `-shm`. These are copied to a temporary directory before opening, so the live database is never opened for writing.

Transcripts contain your prompts and the model's replies. Tokenometer parses only the usage fields (token counts, model, timestamp, session id, working directory name) and discards the rest in memory. No transcript content is stored or displayed.

## Files written

- `~/Library/Group Containers/F5ED28X889.net.timkennedy.tokenometer/snapshot.json`: the current numbers, for the widget. Percentages, token counts, cost estimates, plan name, tool names. No credentials, no transcript content.
- `UserDefaults` for the app: settings only.
- A temporary copy of each Antigravity database during parsing, deleted immediately after.

## Commands run

Tokenometer runs four system tools, all as you, none with elevated privileges:

- `ps` and `lsof`, to find the Antigravity language server and its localhost ports (above).
- `pluginkit -a` on its own widget extension and `killall chronod`, once, the first time a new version of the app launches. Replacing the app makes macOS drop the old widget extension, and without this the widget stays on its old drawing or goes blank. `chronod` is the system's widget service and restarts by itself; every app's widgets redraw for a moment. Source: `Tokenometer/WidgetRepair.swift`.

## Network

Every outbound request, with purpose:

| Destination | When | Sends | Receives |
|---|---|---|---|
| `127.0.0.1:<port>` (Antigravity language server) | at most every 2 min active, 5 min idle, only while Antigravity runs | CSRF token | quota groups, plan name |
| `github.com/tksunw/Tokenometer/releases/…` (Sparkle) | once a day when "Check for updates automatically" is on (the default), or when you choose Check for Updates | nothing beyond a plain HTTPS GET; Sparkle's system profiling is disabled in `Info.plist` (`SUEnableSystemProfiling = false`) | `appcast.xml`, then the release disk image if you accept an update |

That is the complete list for Tokenometer. The usage-reporter mod's one request, to `api.anthropic.com/api/oauth/usage`, is made by Claude Code, not by Tokenometer. Updates are verified two ways before Sparkle installs them: an EdDSA signature in the appcast against the public key baked into the app (`SUPublicEDKey`), and Apple's code signature on the downloaded app. `Scripts/release.sh` produces the appcast with Sparkle's `generate_appcast`, which signs with the private key held in the author's login keychain; the private key is not in the repository.

## Build integrity

Releases are built with `Scripts/release.sh`: Xcode archive, Developer ID export, Apple notarization, stapling, then a signed and notarized disk image. The signing team is `F5ED28X889`. You can verify a download with `spctl -a -vv -t exec Tokenometer.app` and `codesign -dv --verbose=2 Tokenometer.app`.

## Reporting

Open a GitHub issue for anything in this document that the code does not match, or email the address in the repository profile for something you would rather not post publicly.
