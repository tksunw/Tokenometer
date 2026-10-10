# Widgets: layout rules and how they got here

Handoff for whoever touches `TokenometerWidget/` or `TokenometerCore/Sources/TokenometerUI/` next. Covers releases 1.2.0 through 1.2.2 (October 2026): the Session Rings widget, the reset-time format, the layout rules both widgets follow, and the chronod bug that hid the new widget on one Mac.

## What exists

One extension, two widgets, registered in `TokenometerWidget/TokenometerWidget.swift`:

- `TokenometerWidget` (kind `TokenometerWidget`), bars. `StaticConfiguration`, small, medium, large. Drawn by `WidgetContentView` over `UsageBarView` (per-row bar) and `WidgetProviderView` (the large's per-provider block). `ViewThatFits` tries type scales 1.4 down to 1, then a fallback without reset times.
- `TokenometerRings` (kind `TokenometerRings`), rings. `AppIntentConfiguration` with `RingsConfigurationIntent` in `TokenometerWidget/RingsWidget.swift`: a Bool parameter per provider (Anthropic, OpenAI, Google, all default on; all off means all) and a `RingShape` enum (ring or 240° gauge). Each placed widget keeps its own, so several can sit side by side with one provider each. Drawn by `RingWidgetView` over `SessionRing`. Small, medium, large; the large adds a weekly row; one provider alone draws large with its weekly ring beside it on the medium and large.

Both share `TokenometerUI` with the menu and the `mockups` executable, so `swift run mockups ../docs/images` renders the README screenshots from the real views with `SampleData`. Run it after any view change; the `rings-*.png` files come from it too.

## The rules

Agreed in a design review on 2026-10-10 (canvas: Tokenometer Widget Review). Apply them to any new widget or row.

1. Left is for names. Provider name, window label, column header, spend label. The provider dot appears only beside a left-aligned name.
2. Right is for numbers. Percent, reset time, spend, "as of", all right-aligned on one trailing edge, the end of the bar.
3. Centered only on a ring. Inside a ring column everything sits on the ring's axis. No centered text elsewhere, titles included.
4. One footer. "as of 10:12 AM", bottom right, 10pt secondary, in every size that has a footer (medium and large). Never in a header.
5. Two words for windows. "Session" and "Weekly". Never "5h", "wk", "Week". Scoped windows keep their group plus the word: "Fable weekly", "Gemini session", "Claude & GPT session".
6. Session before weekly, in rows and ring rows, per group. `AntigravityLocalClient.parse` sorts each group's buckets that way; the server lists weekly first.
7. One reset string. `Format.resetsShort`: "⟳ 12:38 PM" today, "⟳ Wed 7:49 PM" within six days, "⟳ Oct 16, 7:49 PM" beyond. The menu's `Format.resets` adds "today". Weekday rather than date because a weekly window never resets more than seven days out; the date form stays for anything further (the Enterprise monthly budget has no reset date at all).
8. Names by width. Company name (Anthropic) in a column 100pt or wider, product name (`Provider.shortName`: Claude, Codex, Gemini) below that. A reset line only in a column 60pt or wider, so the small with three rings has none.
9. One type scale. Provider name 10pt bold, row label 10pt, percent 10pt bold monospaced in the provider's color, secondary 10pt. Ring percent follows the ring: 10, 13, 15, 17, 20, 28pt for 40, 52, 64, 72, 88, 120pt rings; captions 9pt under a 52pt ring, 10pt above.
10. Bars line up. Fixed label, percent and reset columns; the bar takes the rest. Large bars: label 112pt (fits "Claude & GPT session"), percent 30pt, reset 92pt (fits "⟳ Sep 28, 7:49 AM"), bar minimum 60pt. At scale 1 that is exactly the 312pt content width; a larger scale does not fit and `ViewThatFits` steps down.

Rings skeleton, every size: a 12pt header line on the top padding (provider name with dot for one provider, "Session" or "Weekly" row label otherwise), 6pt gap, the rings, remaining space, footer. The header is fixed height so the rings start at the same y in every variant. Ring size by column count, not provider count: medium 64pt always (header + 64pt ring + name + reset + footer is 126 of 132pt; 72pt overflowed and SwiftUI squeezed the header down, which is how the misalignment in 1.2.1's follow-up was found), small 88/52/40 for one/two/three columns, large 72 and 120 for one provider.

## Why some things are the way they are

- Large bars keep the reset time on the row, not under the bar. Nine rows plus a line under each needs about 430pt; the large has 312. Measured by rendering the mock at 520pt tall. Hence the wider reset column and the narrower bar.
- Small bars widget with three rings has no reset times: 44pt per column, "⟳ 12:38 PM" needs about 52.
- The gallery shows each widget once per size with its default configuration. Single-provider and two-provider rings are reached by placing a widget, right-click, Edit Widget. WidgetKit offers no way to list configured variants in the gallery.
- Scoped windows come with their labels from the sources (`"\(group) weekly"` from Antigravity, "Fable weekly" from usage-reporter). The old widget abbreviated them with string replacement (`compactLabel`); that is gone. If a label ever exceeds 112pt at 10pt, widen the column and shrink the bar minimum, or shorten the group name in `AntigravityLocalClient.shortName`, not the window word.

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
- 1.2.2: the ten rules above; large bars labels spelled out and columns resized; scoped windows ordered session first; rings skeleton with fixed header and column-based ring sizes.

## Checks before changing a widget

- `cd TokenometerCore && swift run mockups ../docs/images` and look at every `widget-*.png` and `rings-*.png`. The renderer frames are the sizes chronod reports on macOS 27 (164x164, 344x164, 344x344), so a layout that fits the mock fits the widget.
- `swift test`; `UsageClientTests.firstGroupIsSessionAndWeeklyOthersAreScoped` pins the scoped order.
- `Scripts/install-debug.sh`, then look at the real widgets. Never build to DerivedData while the app sits in /Applications.
- A new widget kind or a new `AppIntent` parameter needs a build number bump to reach other Macs' galleries; see the chronod section.
