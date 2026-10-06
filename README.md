# 4everActionTimeline

A live action timeline for **WoW: Forever**: what you just did and what is
about to happen, laid out around a now line.

> **Status: early build.** Live swing lanes (main hand, off hand, ranged),
> the GCD lane, the cast lane and spell cooldown lanes. Cast each tracked
> spell once out of combat so its cooldown is learned
> (`/actiontimeline calibration` shows what is known).

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
| `/actiontimeline perf` | renderer frame time (average and worst) |
| `/actiontimeline help` | list commands |

## Requirements

- WoW: Forever (the Forever beta client, interface 16000+).
- LibClassicSwingTimerAPI ships embedded — no separate installation.

## Development

Design: `docs/SPEC.md` (behavior), `docs/VISUAL.md` (look),
`GLOSSARY.md` (vocabulary), `docs/adr/` (decisions). Agent guidance:
`AGENTS.md`. Like 4everSwingTimer, this addon holds no swing math — all swing
state comes from
[LibClassicSwingTimerAPI](https://github.com/Ralgathor/LibClassicSwingTimerAPI).
