# 4everActionTimeline

A live action timeline for **WoW: Forever**: what you just did and what is
about to happen, laid out around a now line.

> **Status: early build.** Live swings (main hand, off hand, ranged), the
> GCD, your casts and spell cooldowns, on one track (Single lane) or a lane
> each (Detailed), in Blizzard's own timeline art or a flat look,
> horizontal or vertical. Cast each tracked spell once out of combat so its
> cooldown is learned (`/actiontimeline calibration` shows what is known).

## What it will show

- **Swing lanes** — main-hand, off-hand and ranged: past landings, the next
  landing, and the cadence of the swings after it.
- **GCD lane** — your global cooldown windows.
- **Cast lane** — your casts and channels, including stopped and
  interrupted ones.
- **Spell lanes** — one per tracked spell: when you cast it and when it
  comes back.

Things that happened are drawn in full color; predictions are desaturated,
so you can tell fact from forecast at a glance.

Two layouts, chosen in the settings. **Single lane** (the default) puts
everything on one track for reading from the corner of your eye: swings as
diamonds above and below it, casts as a bar, the GCD as a faint band, the
cooldowns that are about to return growing as they near the now line, and
the spells you can press now in a row of fixed slots under it. **Detailed**
gives each swing, cast and spell a lane of its own.

## What it will not show

WoW: Forever hides some combat data from addons, and this timeline never
invents what it cannot see:

- No proc buffs, crits, damage, or hit/miss/dodge/parry results on your
  swings — that data exists only in the combat log, which Forever refuses
  to addons.
- No target swing timer — Forever provides no API for it.
- No "press this next" advice — out of bounds by design.

## Commands

| Command | Action |
|---|---|
| `/actiontimeline` | status (version, library check) |
| `/actiontimeline config` | the lane list: which spells get a lane, engine lanes, manual cooldowns, drag to reorder |
| `/actiontimeline options` | open the settings (also under Options > AddOns) |
| `/actiontimeline test` | toggle test mode: fake swings, casts and cooldowns on a running clock |
| `/actiontimeline test effects` | replay the swing effects (parry, early landing, reset, swap, overdue, retry) |
| `/actiontimeline test off` | stop test mode |
| `/actiontimeline show combat \| always \| active` | when the timeline shows: in combat (default), always, or while anything is on it |
| `/actiontimeline lane <spell> on \| off` | track or stop tracking a spell's cooldown (for your class) |
| `/actiontimeline override <spell> <seconds \| clear>` | set this character's cooldown for a spell by hand |
| `/actiontimeline sink <spell> on \| off` | an engine-drawn lane for a spell: its true remaining cooldown, placed by the game itself (up to 6) |
| `/actiontimeline sink countdown on \| off` | show the engine's own countdown on those icons (needs the game's "show cooldown numbers" option) |
| `/actiontimeline calibration [wipe]` | what each tracked spell's cooldown is known as (or forget them all) |
| `/actiontimeline debug` | each spell lane's live state and the last casts (for bug reports) |
| `/actiontimeline debug layout` | the layout, then each lane frame and its track line as the client sees them: skin, orientation, scale (for bug reports) |
| `/actiontimeline perf` | renderer frame time (average and worst) |
| `/actiontimeline help` | list commands |

Move the timeline in **Edit Mode**: open Edit Mode and drag the
"4everActionTimeline" handle.

## FAQ

**Why does a parried or missed swing look the same as a hit?** Swing marks
are outcome-agnostic on purpose: whether a swing hit, crit, missed, was
dodged or parried is only in the combat log, which Forever refuses to
addons. A mark means "the swing happened", nothing more. What the timeline
does show is swing *timing* the game reports — an early landing, a clip,
a delayed shot.

**Why are some hollow diamonds frozen?** In Single lane a hollow diamond is
the ranged hand, and a hand that is paused (for example while you cast) keeps
its marks still, with a small pause glyph on the next one. Test mode pauses
the ranged hand on purpose, every 10 s.

**Why are some icons faded?** Faded (desaturated) means a prediction;
full color means the game confirmed it. Blue and grey tints on a ready
spell are Blizzard's own action-bar colors: not enough resource, and not
usable.

## Requirements

- WoW: Forever (the Forever beta client, interface 16000+).
- LibClassicSwingTimerAPI ships embedded — no separate installation.

## Development

Design: `docs/SPEC.md` (behavior), `docs/VISUAL.md` (look),
`GLOSSARY.md` (vocabulary), `docs/adr/` (decisions). Agent guidance:
`AGENTS.md`. Like 4everSwingTimer, this addon holds no swing math — all swing
state comes from
[LibClassicSwingTimerAPI](https://github.com/Ralgathor/LibClassicSwingTimerAPI).
