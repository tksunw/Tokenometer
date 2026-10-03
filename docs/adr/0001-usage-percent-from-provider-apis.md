---
status: superseded by ADR-0004 and ADR-0005
---

# Usage percent comes from provider usage APIs, everything else from logs

The design rule is "read what the agents log, never instrument the session." Only Codex writes usage percent to its logs. Claude Code and Gemini CLI fetch it from a provider API at runtime (`/usage` and `/stats`) and never persist it. We decided that Tokenometer calls those same usage endpoints itself, reusing the credentials each CLI already stores on the Mac (Claude Code's login keychain item, Gemini's `oauth_creds.json`), and reads nothing else over the network. Spend stays log-derived for every provider.

Superseded. ADR-0004 moved the Anthropic call into a Claude Code mod, and ADR-0005 removed the Gemini Code Assist call. Tokenometer no longer reads any provider login or calls any provider.

## Considered options

- Statusline tap for Claude: a statusline command that writes the `rate_limits` JSON Claude Code pushes to it. Documented fields, but needs per-Mac configuration and chains into whatever statusline is already set. Kept as the fallback design if the usage endpoint breaks.
- Estimate percent from token math against plan limits. Limits are undocumented and shift, so the bar would lie.
- Spend only, no percent for Claude or Gemini. Defeats the purpose of the bars.

## Consequences

- The endpoints are undocumented and can change without notice. Treat a failing call as "stale", keep the last good value, never block spend display on it.
- Tokenometer must never refresh or rewrite a CLI's stored token in a way that could log the CLI out. If a token is expired, wait for the CLI to refresh it.
- Codex needs no network call; its percent is read from logs like everything else.
