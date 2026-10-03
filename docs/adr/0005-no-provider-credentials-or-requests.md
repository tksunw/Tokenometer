---
status: accepted
---

# Tokenometer reads no provider credential and makes no request to a provider

ADR-0001 had Tokenometer reuse the logins the CLIs store and call each provider's usage endpoint. ADR-0004 moved the Anthropic call into a Claude Code mod. What remained was the Google Code Assist fallback: read `~/.gemini/oauth_creds.json`, identify as Gemini CLI, and call `cloudcode-pa.googleapis.com/v1internal`. That is the same pattern ADR-0004 removed, a third-party app presenting another tool's login to an internal endpoint, and it only ever answered for licensed Workspace and enterprise accounts. We decided to delete it, along with the `tokenometerctl` probes that read Google logins. Tokenometer now reads no credential of any provider and sends nothing to any provider's servers. This supersedes ADR-0001.

Usage percent comes from three places, none of them a provider request made by Tokenometer: Codex's own logs, the file the usage-reporter mod writes (ADR-0004), and the Antigravity language server on localhost (ADR-0003).

## Consequences

- Gemini CLI accounts on a Workspace or enterprise license lose their percent bars and show spend only, unless Antigravity is running. Nobody in the household is on one.
- The only network traffic Tokenometer originates is the Sparkle update check and the localhost call to Antigravity.
- What was learned while probing stays written down so it is not repeated: Google's Code Assist quota endpoints refuse consumer logins (`UNSUPPORTED_CLIENT`, then a license 403) with any token and any client identity. Do not reintroduce a provider call to get around a missing number; the bar goes stale or shows spend.
