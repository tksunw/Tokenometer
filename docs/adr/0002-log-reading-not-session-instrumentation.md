---
status: accepted
---

# Usage is derived by reading agent logs after the fact, never by instrumenting sessions

Other token counters hook the session start, wrap the agent binary, or proxy its API traffic. Tokenometer reads the transcripts and session files the agents already write (`~/.claude/projects`, `~/.codex/sessions`, `~/.gemini/tmp/*/chats`, Claude Desktop local agent sessions) and recomputes from them on change. Nothing Tokenometer does changes how an agent runs, and uninstalling it leaves no trace in any agent's config. ADR-0004 is the one exception: a Claude Code mod that observes two session events to report usage percent, installed by the user and removed by deleting its folder.

## Consequences

- Retention is bounded by each agent's own pruning (Claude Code and Gemini CLI default to 30 days). Tokenometer keeps no history of its own; it is a real-time view.
- Subagent transcripts count toward spend; the PowerShell script skipped them and the Swift parsers must not.
