# A separate addon, a second consumer of the swing library

Status: accepted (2026-10-05, recorded 2026-10-06).

The action timeline ships as its own addon in its own repo, embedding
LibClassicSwingTimerAPI through the same externals trio, rather than as a
timeline mode inside 4everSwingTimer. 4everSwingTimer's scope is
deliberately narrow — swing bars, no swing math, every swing value from the
library — and a timeline brings casts, cooldowns, calibration caches,
per-class curated data and its own settings window, none of which a swing
bar needs. Keeping them apart preserves the bar addon's small, verified
surface and makes the library's consumer contract explicit: two addons
reading the same events prove the library is the sole source of swing
state, with no math leaking into either consumer.

## Considered options

- Timeline mode inside 4everSwingTimer: rejected — it would grow the bar
  addon's scope, settings and verification checklist several-fold, and tie
  the timeline's release cadence (probe-gated lanes, curated data) to an
  addon that is already shipped and stable.
- Timeline as a plugin addon that depends on 4everSwingTimer: rejected —
  couples two release pipelines and puts a load-order dependency where the
  embedded library already gives both addons the same data.

## Consequences

Two addons embed the same library; LibStub serves the highest MINOR, so
each addon gates on its own required MINOR and loads inert below it. Swing
and secrecy terms stay canonical in the 4everSwingTimer glossary; this
repo's glossary links to it rather than copying them. The bar addon's effect colors
(teal, amber, red) are imported by convention, not by code.
