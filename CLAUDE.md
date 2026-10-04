# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project goal

Tokenometer is a macOS menu bar app with a desktop widget that shows, per AI provider, how much of the session window and weekly window has been used, as bars. One color per provider (Anthropic, OpenAI, Google). Audience is a household (three Macs, all on macOS 27), distributed as a signed, notarized GitHub release with Sparkle updates. Read `GLOSSARY.md` for terms and `docs/adr/` for the decisions that shape the design.

## Current state

Design settled; Core package and app scaffold exist. The repo holds `Get-ClaudeUsage.ps1`, a PowerShell script that scans local agent logs and reports tokens and estimated cost. It is the reference for the math and for where usage data lives, frozen once the Swift parsers pass fixture tests. It is not the app.

Layout: `TokenometerCore/` (Swift package: model, parsers, collectors, pricing, aggregation, tests with fixtures under `Tests/TokenometerCoreTests/Fixtures/`), `Tokenometer/` (menu bar app), `TokenometerWidget/` (WidgetKit extension), `Scripts/` (fixture scrubbing and protobuf dump helpers).

## Commands

```bash
cd TokenometerCore && swift test                      # parser, pricing, aggregation tests (CI runs this)
cd TokenometerCore && swift test --filter CodexParser # one suite
cd TokenometerCore && swift run tokenometerctl         # live diagnostic: collectors plus usage sources, prints a summary
cd TokenometerCore && swift run tokenometerctl --collectors   # per-collector record and failure counts, no network
cd TokenometerCore && swift run mockups ../docs/images       # re-render README screenshots from the real views with SampleData
xcodegen generate                                     # regenerate Tokenometer.xcodeproj after editing project.yml
xcodebuild -project Tokenometer.xcodeproj -scheme Tokenometer -configuration Debug -destination 'platform=macOS' build
Scripts/install-debug.sh                              # build Debug, install over /Applications, re-register the widget, restart chronod
pwsh ./Get-ClaudeUsage.ps1 -GroupBy Tool -Days 0      # reference script, all time
Scripts/release.sh 1.2.3                              # archive, Developer ID export, notarize, zip, DMG, appcast (needs a notarytool keychain profile and dmgbuild)
```

The built app writes its snapshot to `~/Library/Group Containers/F5ED28X889.net.timkennedy.tokenometer/snapshot.json`. That directory is TCC-protected from a shell, so use `tokenometerctl` to see what the app sees.

Never run a DerivedData build while a copy sits in /Applications: WidgetKit validates the widget against the registered app bundle and fails every reload with "Bundle version did not match". Test through `Scripts/install-debug.sh`. If widgets stop updating or go blank after any install, `pluginkit -a <appex> && killall chronod` clears it. The app does this itself the first time a new build number launches (`Tokenometer/WidgetRepair.swift`, keyed on `lastLaunchedBuild` in UserDefaults), because a Sparkle update or a drag from the DMG replaces the bundle and chronod drops the extension ("LS doesn't have a containing bundle, removing existing version as a safeguard").

`project.yml` is the source of truth for targets, entitlements, Info.plist keys, and the Sparkle dependency. Edit it and regenerate; do not hand-edit the pbxproj. The generated project is committed so clones build without xcodegen.

Toolchain: Xcode 27, Swift 6.4, xcodegen 2.46, pwsh. Signing is manual with the Developer ID Application identity for team F5ED28X889, even for Debug builds. The App Group is team-prefixed (`F5ED28X889.net.timkennedy.tokenometer`, not `group.`) because a `group.` identifier needs a provisioning profile on macOS and Developer ID distribution has none.

## Decisions in force

- Log reading only, never session instrumentation (ADR-0002). Exceptions: Claude usage percent comes from the file the separate `usage-reporter` Claude Code mod writes, with Claude Code making the usage call on its own login (ADR-0004, supersedes ADR-0001 for Anthropic); Tokenometer never reads the Claude login and never contacts Anthropic; Google usage percent comes from the running Antigravity language server on localhost (ADR-0003). Tokenometer reads no provider login and makes no request to any provider (ADR-0005): never read the Claude keychain item, `oauth_creds.json`, or Antigravity's keychain login, and never add a provider call to recover a missing number.
- Real-time view only. No history store. Recompute from logs on FSEvents change (2 to 3 s debounce) plus a 60 s timer. The Antigravity localhost call: on debounced log change with a 2 min floor, every 5 min when idle. The Claude usage endpoint rate-limits callers (429 observed after a handful of calls in a few minutes); the usage-reporter mod calls it at most once per 5 min across sessions and waits 10 min after a 429. `tokenometerctl --claude-raw` prints the mod's file and calls nothing. Windows go stale when the logs are more than 15 min newer than the last report (`UsageEngine.reportLag`).
- Plan accounts show usage percent; metered accounts (API key, Enterprise) show spend against an optional user-set budget, numbers only until a budget exists. Detection is automatic per provider with a settings override.
- A provider appears only when its data directory exists. Degraded sources keep the last value, marked stale with age and reason.
- Dollars on plan accounts are API-equivalent cost, labeled. Pricing is a hardcoded table; unknown models show tokens and "?" for cost, never a silent fallback.
- Targets: `Tokenometer` app (menu bar only, `LSUIElement`), `TokenometerWidget` (small, medium, large), `TokenometerCore` local Swift package with collectors, parsers, model types, and Swift Testing tests against fixtures in `TokenometerCore/Tests/TokenometerCoreTests/Fixtures/`. App Group `F5ED28X889.net.timkennedy.tokenometer`. Widget reads a snapshot from the App Group; the app writes it and reloads timelines.
- GitHub repo `tksunw/Tokenometer`, MIT. README.md, SECURITY.md, PRIVACY.md describe behavior to outsiders; any change to what is read or sent must update SECURITY.md and PRIVACY.md in the same change. Shared SwiftUI views live in `TokenometerUI` so the app, the widget, and the mockup renderer draw the same thing. CI runs Core package tests only; `Scripts/release.sh` does archive, export, notarize, zip, and a notarized drag-to-Applications DMG locally (`Scripts/make-dmg.sh`, dmgbuild, layout in `Scripts/dmg-settings.py`, background from `Scripts/make-dmg-background.swift`, the same approach as InterNos). Sparkle is live: `Updater.swift` starts `SPUStandardUpdaterController`, `SUPublicEDKey` is in `project.yml`, `Scripts/release.sh` runs `generate_appcast` over the DMG (EdDSA key in the login keychain, shared with InterNos) and the appcast.xml is uploaded next to the DMG and the zip; bump `CURRENT_PROJECT_VERSION` with every release, since Sparkle compares it, not the marketing version; `SUFeedURL` points at `releases/latest/download/appcast.xml`; both repos are public, so the feed resolves.
- One account per provider per Mac.

## Data sources

Anthropic:
- Claude Code: `~/.claude/projects/**/*.jsonl`, including `subagents/` dirs (the script skips them; the app must not). Only `assistant` entries carry `message.usage` and `message.model`. Dedupe by `message.id`, keep the last entry. `cost-state` entries carry per-session `totalCostUSD` and `modelUsage`.
- Claude Desktop (Cowork and Code): `~/Library/Application Support/Claude/local-agent-mode-sessions/**/.claude/projects/**/*.jsonl`, same format. Sibling `audit.jsonl` is SDK stream-json with `rate_limit_event` (window type, status, reset time, no percent).
- Usage percent (ADR-0004): from `~/.claude/usage-reporter/usage.json`, written by the `usage-reporter` Claude Code mod, which lives in its own repo (`~/REPOS/usage-reporter`, GitHub `tksunw/usage-reporter`) and is installed per Mac by cloning it into `~/.claude/skills/usage-reporter`. Format 1: `{version: 1, at, windows: [{kind: session | weekly, label?, percent, resetsAt?, at}], weeklyBreakdown?: {rows: [{key, label?, percent}]}, credits?, cloudSessionCredits?, raw?}`; a weekly window with a `label` is model-scoped ("Fable"). `weeklyBreakdown` (usage-reporter 0.3.0) is the weekly usage by surface for the whole account; it becomes `ProviderSnapshot.surfaces` and is drawn in the menu's disclosure under the local tool and model rows. Its `percent` appears to be a share of the week's usage summing to 100, but only one non-zero row has ever been observed, so that is unconfirmed. `credits` and `cloudSessionCredits` are not read. The mod has Claude Code call `https://api.anthropic.com/api/oauth/usage` through `$.session.authorize()` and `$.http.fetch(url, { auth })` (the credential never reaches the mod), at most once per 5 min across sessions, 10 min after a 429, and between calls merges the status line's session and weekly percent into the last report. All knowledge of Anthropic's response shape is in the mod. `ClaudeUsageFile` reads the file on every refresh (`readsLocalFile`) and rejects an unknown `version`. Plan vs metered: `oauthAccount` in `~/.claude.json` means plan (`organizationType`, `organizationRateLimitTier` give "Max 5x"); `organizationType` containing `enterprise` means metered. Never read the `Claude Code-credentials` keychain item.

OpenAI:
- Codex: `~/.codex/sessions/**/*.jsonl`. `event_msg` / `token_count` events carry cumulative `total_token_usage` (take the last per file; `input_tokens` includes `cached_input_tokens`) and `rate_limits.primary` / `.secondary` with `used_percent`, `window_minutes`, `resets_at`, plus `plan_type`. Newest event across files is current. The only provider whose percent is on disk.

Google:
- Antigravity (IDE and the `agy` CLI, which replaced Gemini CLI for individual accounts): both write `~/.gemini/antigravity/conversations/<id>.db`, SQLite in WAL mode. The parser copies db, -wal and -shm to a temp dir and opens the copy read-write (a read-only connection cannot create -shm and fails silently on the first query). Usage comes from `steps.metadata` for `step_type = 15` rows, raw protobuf: field 1 is a Timestamp (seconds, nanos), field 9 the usage message (1 model enum, 2 input, 3 output, 5 cache read, 9 thinking). `gen_metadata.data` path `1.19` has the model name string, one row per call in the same order. Field numbers were inferred from live data, so the parser is flagged experimental. Antigravity routes to Gemini, Claude, and GPT-OSS models under the Google plan; all count as Google. `agy` keeps its own state in `~/.gemini/antigravity-cli/` (summaries db, `history.jsonl`, `log/cli-*.log`), nothing with usage in it.
- Gemini CLI (still used by Workspace and enterprise accounts): `~/.gemini/tmp/<sha256 of project path>/chats/session-*.jsonl` (legacy `.json` must also parse). Line 1 is session metadata; `type: "gemini"` messages carry `tokens: {input, output, cached, thoughts, tool, total}` and `model`. `input` includes `cached`. Pruned after 30 days by default.
- Plan vs metered: `~/.gemini/settings.json` `security.auth.selectedType`; `oauth-personal` is a plan account. `~/.gemini/oauth_creds.json` holds the shared `agy` and Gemini CLI login and is never read.
- Usage percent (ADR-0003): from the Antigravity `language_server` process on localhost. Find it with `ps` (command line has `--csrf_token <token>`; the hub app's has `--subclient_type hub` and stays up in the background), its ports with `lsof -p PID -iTCP -sTCP:LISTEN`; one port is HTTPS with a self-signed cert, the other plain HTTP, and the client tries each with plain HTTP. `POST http://127.0.0.1:PORT/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` with `content-type: application/json`, `connect-protocol-version: 1`, `x-codeium-csrf-token: <token>`, body `{}` returns `response.groups[]` ("Gemini Models", "Claude and GPT models"), each with `buckets[]` of `{window: "weekly" | "5h", remainingFraction, resetTime}`. The first group fills session and weekly; other groups become scoped windows with labels. `GetUserStatus` gives `userStatus.planStatus.planInfo.planName` ("Pro"). `AntigravityLocalClient` implements this and is the only Google source; `tokenometerctl --google` runs it alone.
- Dead ends, removed (ADR-0005): Google's Code Assist quota endpoints (`cloudcode-pa.googleapis.com/v1internal`) refuse consumer logins with `UNSUPPORTED_CLIENT` and a license 403, with any token and any client identity. Antigravity keeps its own login in the keychain; it does not help and is not read. Do not rebuild either.
- Antigravity's `~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb` holds a per-model quota fraction that was months stale; do not use it.

## Platform constraints

- Widget extensions are sandboxed and cannot read home directory logs. All collection happens in the app.
- The app is unsandboxed (direct distribution), which is what lets it read `~/.claude`, `~/.codex`, and `~/.gemini`.
