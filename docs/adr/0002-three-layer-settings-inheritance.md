# Three-layer settings inheritance: shipped defaults, class, player

Status: accepted (2026-10-06).

The lane set and per-spell settings resolve through three layers: the
addon's shipped defaults (the curated per-class starter set), the class
layer (shared by every character of that class), and the player layer
(this character's overrides). Each layer stores only what was changed at
that level; an unset key falls through to the layer below. We chose this
over the earlier two-layer model, where the class layer was seeded from the
shipped defaults on first load: seeding is copy-on-first-use, so starter-set
improvements in later releases would never reach an existing install — the
same flaw already rejected between the player and class layers.

## Considered options

- Two layers, class seeded from shipped defaults: rejected — freezes the
  starter set at first install.
- Copy-on-first-use per player: rejected earlier — class-set improvements
  never reach alts.

## Consequences

The shipped defaults are a code-side table, never written to saved
variables; a release that changes them changes every unset key at once, so
starter-set edits are release-noted. A "reset to class" or "reset to
default" action is a key deletion at the matching layer. Calibration
data is not a setting and stays outside this chain, in the player layer's
separate cache sub-table.
