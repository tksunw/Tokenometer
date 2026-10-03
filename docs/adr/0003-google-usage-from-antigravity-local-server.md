---
status: accepted
---

# Google usage percent comes from Antigravity's local language server

Google's Cloud Code quota endpoints (`retrieveUserQuota`, `retrieveUserQuotaSummary`) refuse consumer logins: a Google AI Pro account gets `UNSUPPORTED_CLIENT` from `loadCodeAssist` and a license 403 from the quota calls, with either the Gemini CLI token or Antigravity's own keychain token. Yet the Antigravity IDE and the `agy` CLI show per-group quota. They get it from the `language_server` process Antigravity runs on localhost, which serves Connect-JSON RPCs: `exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` returns a "Gemini Models" group and a "Claude and GPT models" group, each with a weekly and a 5-hour bucket (`remainingFraction`, `resetTime`); `GetUserStatus` returns the plan name. We decided to read those RPCs from the running hub process, found by its command line (`--csrf_token`, `--subclient_type hub`) and its listening ports. The Code Assist client was kept at first as a fallback for licensed Workspace accounts and later removed (ADR-0005).

## Considered options

- Code Assist endpoints with Antigravity's OAuth client token. Same refusals; the token is not what the server keys on.
- Reverse-engineering the remote RPC the language server itself calls. Unlogged, probably gRPC with client-specific identity; brittle and undocumented.
- Spend only for Google. Loses the one number the bars exist for.

## Consequences

- Google percent exists only while an Antigravity process is running. When none is, the bars go stale with "Antigravity is not running" and keep their last values. The hub app normally runs in the background, so this is rare in practice.
- This is a process-local API with no stability promise; an Antigravity update can rename the RPC or change the CSRF header. The parser is isolated in `AntigravityLocalClient`; when it fails the bars go stale.
- Discovery shells out to `ps` and `lsof`; neither needs privileges for the user's own processes.
