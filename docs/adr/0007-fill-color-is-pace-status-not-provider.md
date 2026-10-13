---
status: accepted
---

# A window's fill is colored by pace status, not by provider

Through 1.3 every bar and ring took its provider's color (clay, teal, blue) and turned amber from 75% and red from 90% when usage was ahead of the clock. Two problems: the provider color said who a bar belonged to, which the logo tile now says better; and "amber from 75%" ignored how far through the window the clock was, so a window at 76% an hour from its reset looked as alarming as one at 76% an hour after it began.

We decided the fill carries one meaning, whether usage is running ahead of the pace tick, and the provider's identity lives on its logo tile. Green while usage is at or behind the tick, or ahead by less than 10 points. Yellow once it leads the tick by 10 points or more. Red when it is past the tick at 90% or more ("time to wrap it up"). The whole fill takes the color. With no reset time there is no tick, and the old absolute rule applies (yellow from 75%, red from 90%). A setting swaps the three colors for the Okabe-Ito set (sky blue `#56B4E9`, orange `#E69F00`, vermilion `#D55E00`), because red, yellow, and green are the worst trio for red-green color blindness. The tick and the percent stay as the other cues.

Settings has a Colors selector with three choices: traffic light (the default above), color-blind friendly (the Okabe-Ito set), and Provider. Provider draws every fill in its provider's color (clay, light purple, blue) whatever the status: no yellow, no red. The pace tick and the elapsed share still show how the window stands, but nothing changes color as usage climbs. It is the 1.3 look minus the amber and red escalation, for someone who finds the status colors noisy.

The 10-point floor exists because a window's first minutes put a point or two of use ahead of a tick that is itself near zero; without it the bar flips to yellow at once. Red has no floor because at 90% the window is nearly spent.

Each window also shows how much of its time has passed, the number the tick marks, so the tick is readable as a figure.

## Consequences

- The menu bar item still draws in the provider's color, with the old amber and red escalation: it has no logo to carry identity.
- `Snapshot.palette` carries the choice (`trafficLight`, `colorBlind`, `provider`; a development build wrote `standard` for traffic light and is still read) to the widget, which is sandboxed and cannot read the app's preferences. A palette change counts as new content, so `Snapshot.hasSameContent` reloads the widget timelines.
- `UsageStatus.of(percent:pace:)` is the one rule, and `StatusPalette.color(_:_:provider:)` turns it into a color; menu cards, bars, gauges, and widgets all go through them. `UsageWindow.provider` is a draw-time tag the widget views stamp at their root (`Snapshot.stamped()`) so a helper that holds only a window can still find its provider's color; it is never saved.
