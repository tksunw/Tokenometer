---
status: accepted
---

# Between sessions, Tokenometer starts a throwaway Claude Code session so the mod reports

ADR-0004 moved the Anthropic usage call into the usage-reporter mod, which runs only inside a Claude Code session. Between sessions the file ages: usage from claude.ai chat, Cowork and Claude Desktop goes unseen, a window that reset still shows its old reset time until a session confirms it, and the model-scoped windows and grants freeze. The bars dim after fifteen minutes and blame the mod. We decided that Tokenometer may start a Claude Code session itself, with nothing loaded but the mod, so the mod's `session.start` report lands in the file, then end the session. Claude Code makes its usual usage call on its own login. Tokenometer still reads no credential and sends nothing to Anthropic (ADR-0005), and still reads only `usage.json`.

The session is started in a PTY as `claude --setting-sources "" --plugin-dir <mod> --tools "" --strict-mcp-config --mcp-config '{"mcpServers":{}}' --no-chrome`, from `~/Library/Application Support/Tokenometer/UsagePull/` (mode 0700). No prompt is sent and no token is spent. The mod reports about two seconds after launch; Tokenometer waits for the file's fetch stamp to move (at most twenty seconds), then sends SIGTERM. Measured on Claude Code 2.1.296 with usage-reporter 0.6.2: the report arrives before the folder-trust dialog is answered when the mod loads from settings, and about two seconds after it is answered with `--plugin-dir`; the runner answers it ("Yes, I trust this folder") the first time, and Claude Code records that in `~/.claude.json` for the pull directory. `--safe-mode` drops `--plugin-dir` along with everything else and is not usable.

The mod is found through Claude Code's plugin registry (`~/.claude/plugins/installed_plugins.json`, a marketplace install) or the folders in `CLAUDE_CODE_PLUGIN_DIRS` from `settings.json` (a development copy); when both exist the one `enabledPlugins` marks on is used. With neither, no session is started and the bar says the mod is not installed.

## Considered options

- Call the endpoint from Tokenometer. Rejected by ADR-0005; it also needs the login.
- Scrape Claude Code's `/usage` screen in a PTY, as Lunavect does. Spends nothing, needs no mod, but parses a TUI that changes without notice, and every reader would carry its own parser. The mod already exists and is the one place that knows the response shape.
- Give the mod a timer. A mod runs only inside a session; there is nothing to run between them.
- Leave it. The bars are honest about being stale, but a tool whose point is the number should not go dark for the hours between sessions.

## Consequences

- Each pull is one `GET /api/oauth/usage` by Claude Code, plus the profile call the mod makes every six hours. The mod refuses to call inside its five-minute floor and a session with no turns then writes nothing, so Tokenometer never starts a pull inside the floor, measured from the file's own fetch stamp (a labelled window's `at`, else the breakdown's, grants' or credits', else the file's) rather than its own clock, since any live session can reset the floor at a turn end.
- Nothing from the user's settings runs in that session: no hooks, other plugins, CLAUDE.md, MCP servers or tools. The session leaves an empty `~/.claude/projects/<pull directory>/memory/` folder and a trust entry in `~/.claude.json`; it writes no transcript (`CLAUDE_CODE_SKIP_PROMPT_HISTORY=1`).
- This is a second exception to ADR-0002, narrower than the mod's: a session Tokenometer owns, with no user content in it.
- `tokenometerctl --pull` runs one pull and prints the mod path, the `claude` path, the fetch stamp before and after, and the outcome; `--force` ignores the floor to diagnose the launch itself.
- The pace (how often the app pulls when idle, and at a window's reset or on wake) lives in the app and is documented in PRIVACY.md.
