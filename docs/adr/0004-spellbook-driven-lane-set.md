# Spellbook-driven lane set, not the Cooldown Manager

Status: accepted (2026-10-05, recorded 2026-10-06).

The lane set is discovered by scanning the player's spellbook: every known
class spell is a toggle, a curated per-class starter set ships enabled, and
the scan resolves the current rank each session. We do not build lanes
from Blizzard's Cooldown Manager, which EventHorizon_Infall uses on retail
12.x: on Forever it covered only five classes (Druid, Mage, Priest,
Warrior, Warlock) as of build 70009, is off by default, and does not
support spell ranks. ForeverCDM already proves the spellbook pattern on
this client.

## Considered options

- Cooldown Manager as the lane source: rejected — partial class coverage,
  off by default, rank-blind; the timeline would be empty for four classes.
- Typed spell input or a capture mode (record spells as they are cast):
  rejected — friction, typo-prone, and redundant with the spellbook scan.

## Consequences

The addon owns per-class curated data (starter sets, linked-cooldown and
delayed-start seeds, reset tables) for all nine classes. Lane identity and
the calibration cache key on the resolved spell ID; rank churn is handled
by the scan and by pruning cache entries absent from it. A Cooldown Manager
mirror stays possible as an optional accuracy upgrade (probe 8), never the
foundation.
