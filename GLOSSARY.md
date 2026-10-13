# Tokenometer

Real-time view of how much of each AI provider's usage allowance a person has consumed, read from the logs the agents already write on the Mac. Usage percent comes from what each provider's own tool exposes locally (Codex logs, the usage-reporter mod's file, Antigravity's local server); Tokenometer makes no request to a provider.

## Language

**Provider**:
The company whose account and limits usage counts against: Anthropic, OpenAI, Google. Each has an identity color, shown on its logo tile.
_Avoid_: Agent, vendor, service

**Tool**:
A program that talks to a provider and writes logs: Claude Code, Claude Desktop, Codex, Antigravity, Gemini CLI. Several tools can share one provider account.
_Avoid_: Agent, client, app

**Usage window**:
A rolling period over which a provider caps usage. Every plan account has a short window (the session window) and a long window (the weekly window).
_Avoid_: Period, bucket, quota

**Session window**:
The provider's short usage window. Claude: 5 hours. Codex: the primary window. Google: the 5-hour bucket of the first model group.
_Avoid_: Session, 5-hour limit

**Weekly window**:
The provider's long usage window. Claude: 7 days. Codex: the secondary window. Google: the weekly bucket of the first model group.
_Avoid_: Week, weekly limit

**Pace**:
How much of a usage window's time has already passed, 0 to 100%. The tick on a bar or gauge marks it, and the cards show it as a small white number beside it.
_Avoid_: Elapsed, progress

**Status**:
What color a window's fill takes: ok (at or behind the pace, or under a 10 point lead), caution (10 or more points ahead of the pace), critical (past the pace at 90% or more). See ADR-0007. The Provider palette ignores it and draws every fill in its provider's color.
_Avoid_: Level, severity, tint

**Usage percent**:
How much of a usage window's allowance has been consumed, 0 to 100, as the provider reports it.
_Avoid_: Utilization, used percentage, limit

**Spend**:
Tokens consumed and their estimated dollar cost, computed from logs. Shown for accounts that have no usage windows, and as detail for accounts that do.
_Avoid_: Cost, usage, tokens

**Plan account**:
A subscription account (Pro, Max, Team) with usage windows. Reports usage percent.
_Avoid_: Subscription, consumer account

**Metered account**:
An API key or Enterprise account billed on consumption with no usage windows. Reports spend only.
_Avoid_: API account, pay-as-you-go, enterprise

**Budget**:
A dollar amount a person sets for a usage window on a metered account, so spend can be shown as a percent of something. On Claude Enterprise the admin-set monthly spend limit, as Anthropic reports it, is the budget instead.
_Avoid_: Limit, cap, allowance

**Reset time**:
The moment a usage window rolls over and its usage percent returns to zero.
_Avoid_: Expiry, rollover, resets_at

**Stale**:
A value whose source could not be refreshed; the last good value is shown with its age.
_Avoid_: Cached, offline, unknown

**API-equivalent cost**:
What a plan account's spend would have cost at the provider's published API rates. Shown on plan accounts, labeled as such, since the subscription is the real bill.
_Avoid_: Cost, estimated cost, savings

**Model group**:
Google's unit of quota: a set of models that share one weekly and one session window. Antigravity has a Gemini group and a Claude and GPT group.
_Avoid_: Bucket, tier, family
