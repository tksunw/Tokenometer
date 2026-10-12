# Widgets: layout rules and how they got here

Handoff for whoever touches `TokenometerWidget/` or `TokenometerCore/Sources/TokenometerUI/` next. Covers the 1.4 redesign (October 2026): the Bars and Gauge widgets, the pace-status colors, the layout rules both follow, and the chronod bug that hid a widget on one Mac.

## What exists

One extension, two widgets, registered in `TokenometerWidget/TokenometerWidget.swift`:

- `TokenometerWidget` (kind `TokenometerWidget`), Bars. `AppIntentConfiguration` with `BarsConfigurationIntent`: a Bool per provider, all default on, all off means all. Drawn by `BarsWidgetView`. Before 1.4 this was a `StaticConfiguration`; a placed widget may reset to showing every provider after the update.
- `TokenometerRings` (kind `TokenometerRings`), now the Session Gauges widget. `RingsConfigurationIntent` keeps its name so a placed widget keeps its provider choice; the ring-shape parameter is gone, the half-circle gauge replaced both shapes. Drawn by `GaugeWidgetView`.

Both have small, medium, and large, and one, two, or three providers. Both set `.contentMarginsDisabled()`: the views draw their own 12pt padding (11pt above the header) so the layouts match the mockups to the point. Both share `TokenometerUI` with the menu and the `mockups` executable. `swift run mockups ../docs/images` renders the README screenshots from the real views with `SampleData`; add `--only-widgets` to render all 42 widget variants (three providers, three two-provider pairs, three single providers) into `<dir>/widgets/`, and `--near`, `--colorblind`, `--light` to see yellow and red, the other palette, and light mode.

The building blocks, all in `TokenometerUI`: `ProviderTile` and `ProviderGlyph` (neutral logo stand-ins, no trademarked artwork), `ArcGauge` (the half circle, 112 x 62 box scaled to a width), `StatusBar`, `UsageStatus` and `StatusPalette`, `ProviderSnapshot.windowRows` (every surface's window order and labels), `ProviderCardView` (the menu card).

## The rules

1. Fill color is status, not provider (ADR-0007). Green at or behind the pace tick or less than 10 points ahead, yellow at 10 or more ahead, red past the tick at 90% or more. Provider color is the logo tile only.
2. Every widget has a header row: what it shows on the left ("Session", "Session and weekly", or the provider's logo and name for a single provider), "as of 10:12 AM" on the right. No separate footer row.
3. Every window is labelled and has its reset time (a clock glyph and a bare time). "Session" and "Weekly" are spelled out; scoped windows keep their group plus the word ("Fable weekly", "Gemini session").
4. Session before weekly, then scoped windows, per provider.
5. Medium cards put the logo and provider name left-justified, as the small and large cards do.
6. Fewer providers means bigger content: gauges and bars grow, or a single provider gets a cell per window and a weekly spend card. No dead space.
7. Names in narrow places are `Provider.shortName` (Claude, Codex, Gemini); the menu card uses the product name (Claude, Codex, Antigravity).
8. Frames are the sizes chronod reports on macOS 27: 164x164, 344x164, 344x344 pt, corner radius 22.
9. Text must not wrap or clip at any size or provider combination. Reset times more than a week out lose their time ("Sep 28") where the column is narrow.

## Why some things are the way they are

- The palette choice rides in `Snapshot.palette` because the widget is sandboxed and cannot read the app's preferences. `hasSameContent` includes it, so toggling the setting reloads the timelines; `AppModel.paletteChanged()` rewrites the snapshot at once.
- Large Bars show only weekly spend (on the card header); the old widget's separate session spend line is gone. Large Gauge shows session and weekly per provider only; scoped windows (Fable, Claude & GPT) appear in the Bars widget, the menu, and the one-provider gauge layouts.
- Small single-provider Gemini shows only its own session and weekly, not the Claude & GPT windows.
- The gallery shows each widget once per size with its default configuration (all providers). One- and two-provider layouts are reached by placing a widget, right-click, Edit Widget.

## The chronod descriptor cache

Found when 1.2.0 shipped and one Mac's gallery showed only the bars widget after the Sparkle update. Logged in CLAUDE.md too; the full story:

chronod keeps a per-extension list of widget kinds ("descriptors") cached under the extension's version. It refetches only on a version change, and it fetches the instant LaunchServices registers the new bundle, by asking whatever extension process it has alive. After a Sparkle swap that is the old version's process, which answers with the old list in about a millisecond (`query returned 1 widget descriptors` at 12:18:20.587 on the affected Mac, 1ms after the request). The list is then cached for the new build number and every chronod restart loads it from cache. `pluginkit -r` then `-a` back to back with chronod running is folded into one "updated extension" with the same version and does not refetch. Writing the extension id into chronod's `extensionsPendingDescriptorRefetch` preference does nothing; chronod rewrites that list with its own encoded entries.

What does refetch: unregister, restart chronod so it forgets the extension, kill the old extension process, register again. `WidgetRepair.swift` does that the first time a new build number launches, and `Scripts/install-debug.sh` does it after every install:

```bash
APPEX=/Applications/Tokenometer.app/Contents/PlugIns/TokenometerWidget.appex
pluginkit -r "$APPEX"; killall chronod; sleep 4; killall TokenometerWidget; pluginkit -a "$APPEX"
```

The 4 s wait matters: chronod has to come back and read the registry without the extension before it is registered again. Verify with `log show --last 1m --predicate 'process == "chronod" AND eventMessage CONTAINS "okenometer"' --style compact | grep -E "Refetching|query returned"`; a good run says `query returned 2 widget descriptors`.

Not fixed and not fixable from the app: the race itself. The refetch at registration time happens before the new app launches. Any Mac updating from a build without the sequence (1.2.0 or earlier) to one with it can still land in the bad state once; the next version bump, or the sequence above, clears it.

## Version history

- 1.1.9 and before: one widget, bars, reset times left-aligned under the bar, "tomorrow" wording.
- 1.2.0: Session Rings widget; reset times right-aligned and weekday-formatted; large bars show glyph, day and time on the row.
- 1.2.1: `WidgetRepair` and `install-debug.sh` use the unregister, restart, kill, register sequence.
- 1.2.2: large bars labels spelled out and columns resized; scoped windows ordered session first; rings skeleton with fixed header and column-based ring sizes.
- 1.4.0: card layouts with logo tiles for both widgets; the Rings widget becomes Session Gauges (half-circle arcs); both take a provider choice; fills colored by pace status (ADR-0007) with an optional color-blind palette; headers on every widget; elapsed share of each window.

## Checks before changing a widget

- `cd TokenometerCore && swift run mockups <scratch dir> --only-widgets` (and again with `--near`, `--light --colorblind`) and look at every `widgets/bars-*.png` and `widgets/gauge-*.png`. The renderer frames are the sizes chronod reports on macOS 27 (164x164, 344x164, 344x344), so a layout that fits the mock fits the widget.
- `swift test`; `UsageClientTests.firstGroupIsSessionAndWeeklyOthersAreScoped` pins the scoped order.
- `Scripts/install-debug.sh`, then look at the real widgets. Never build to DerivedData while the app sits in /Applications.
- A new widget kind or a new `AppIntent` parameter needs a build number bump to reach other Macs' galleries; see the chronod section.
