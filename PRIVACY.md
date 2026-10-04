# Privacy

Tokenometer collects nothing. There is no telemetry, no analytics, no crash reporting, no account, and no server operated by the author. The app has no way to phone home because there is nowhere to phone.

## What stays on your Mac

Everything Tokenometer computes stays on the Mac it runs on:

- Token counts, cost estimates, and usage percentages, in memory and in one JSON file in the app's App Group container so the widget can read it.
- Your settings, in the app's `UserDefaults`.

Nothing is synced, uploaded, or shared with other apps beyond the widget.

## What leaves your Mac

Nothing goes to any AI provider. Tokenometer does not contact Anthropic, OpenAI, or Google, and does not read the logins their tools store.

- Claude: if you install the usage-reporter mod, Claude Code itself asks Anthropic for your usage with its own login and the mod saves the answer to a file on your Mac. Tokenometer reads that file and never sees the login.
- Google: the quota lookup is a localhost call to the Antigravity process already running on your Mac and does not leave it.
- OpenAI: Codex writes its limits into its own logs, which Tokenometer reads like any other log.

The only traffic that leaves your Mac is the update check described under Third parties.

[SECURITY.md](SECURITY.md) lists every request, every file read, and every credential, with the source file that performs each.

## What Tokenometer reads

The log files your AI tools write. Those files contain your prompts and the models' replies. Tokenometer parses only the usage fields (token counts, model, timestamp, session id, project folder name) and discards the rest as it reads. It never stores, displays, or transmits prompt or reply content.

## Third parties

Updates. Tokenometer uses the Sparkle framework to check for new versions, once a day by default or when you ask. The check is a plain HTTPS GET of an `appcast.xml` file on GitHub Releases, and a download of the new app if you accept it. Sparkle's optional system-profile reporting (which can send OS version, CPU, and memory to the update server) is disabled and never enabled. The check can be turned off in Settings. GitHub sees the request the way it sees any download, which is governed by GitHub's privacy statement, not ours.

## Changes

This document describes the behavior of the version it ships with. Any change to what is read or sent will be reflected here and in SECURITY.md in the same release.
