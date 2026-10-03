---
status: accepted
---

# Claude usage percent comes from a Claude Code mod, not from Tokenometer calling Anthropic

ADR-0001 had Tokenometer read Claude Code's OAuth token from the keychain and call Anthropic's usage endpoint itself. Anthropic's published policy for Claude Code says OAuth is for Claude Code and its other native applications, and that developers may not collect, store, or intermediate Claude.ai credentials. An outside app holding the token is on the wrong side of that, and the account at risk is the user's paid subscription. We decided that Tokenometer never reads the Claude login and never contacts Anthropic. A Claude Code mod, `usage-reporter`, kept in its own repository so any tool can use it, asks Claude Code to make the usage call with `$.session.authorize()` and `$.http.fetch(url, { auth })`, where the engine attaches the credential and the mod never sees it, and writes `~/.claude/usage-reporter/usage.json` in a small versioned format (`version`, `at`, `windows[]` of kind, label, percent, reset time). Tokenometer reads that file and knows nothing of Anthropic's response shape. This supersedes ADR-0001 for Anthropic and is a deliberate exception to ADR-0002: the mod hooks `session.start` and `session.measure`, observes only, and changes nothing about how a session runs.

## Considered options

- Keep ADR-0001. Always fresh and needs no setup, but it is the behavior the policy text describes, with enforcement "without prior notice".
- Statusline tap. Documented `rate_limits` fields, no network call at all, but only the 5-hour and 7-day windows, so the model-scoped weekly bar is lost, and it chains into whatever statusline script each Mac already has.
- A mod that writes only `session.measure`'s `rateLimits`. Same two windows as the statusline without touching it. Kept as what the mod writes between usage calls and when one fails.
- A browser extension scraping claude.ai. Still automated extraction, holds the web session, and only updates while a tab is open.

## Consequences

- The numbers move only while a Claude Code session is running. Usage from claude.ai chat or Claude Desktop shows up at the next Claude Code turn. Tokenometer marks the windows stale when the logs are more than fifteen minutes newer than the last report, which is also how a missing or broken mod shows itself.
- Each Mac needs the mod installed once (`~/.claude/skills/usage-reporter/`). Without it the Anthropic bars say the mod has not reported and spend still works.
- The usage endpoint is still undocumented. The mod is the only code that knows its URL and parses its response; when Anthropic changes it, the fix is in usage-reporter and the file format stays. Tokenometer refuses a format version it does not know rather than guessing.
- Splitting the mod out means Tokenometer's repository holds no call to Anthropic at all, and one mod serves every reader, which matters because the endpoint rate-limits: several tools each calling it would starve each other.
- The mod calls the endpoint at most once per five minutes across all sessions (the floor lives in the mod's `$.store`), ten minutes after a 429. Inside the floor it writes the session and weekly percent Claude Code hands it on `session.measure`, laid over the last full response, so those two bars follow each turn and only the model-scoped bar waits for the next call. Those figures trail the endpoint by a point, so within one window the mod never lets a lower reading replace a higher one.
- Reading the file costs nothing, so Tokenometer reads it on every refresh and watches its folder; the two and five minute pacing applies only to sources that make a request.
- The mod API is new and typed per Claude Code build. If it moves, the fix is in the mod; the file format stays.
- Plan name ("Max 5x") now comes from `oauthAccount` in `~/.claude.json` instead of the keychain item.
