# ADR-0008: Configuration in three places, the way Blizzard's own frames do it

Status: accepted (2026-10-13)

Supersedes the "Settings surface split" and the Edit Mode part of "Frame
anchoring" in `SPEC.md` (the frame is still not a registered Edit Mode system,
ADR from probe 9).

## Context

The addon kept 21 settings in the Settings category, the frame's position (one
per character) in Edit Mode behind an orange drag band, and the spell list in a
row-and-checkbox window. Forever's own UI source (build 70338, the `forever`
branch of the wow-ui-source mirror) shows how Blizzard configures a frame like
this one: the Cooldown Manager and the new Swing Timer put the frame's
position and shape settings in **Edit Mode** (scale, opacity, width, height,
visibility), what they show in a **content window** (the Cooldown Manager's
settings window: icon sections, drag between them, a right-click menu, search,
a layout dropdown, Revert), and the rest in **Options**, with buttons linking
the three.

## Decision

- **Edit Mode** holds the frame. It wears Blizzard's selection art; a click
  opens a settings panel (scale, opacity, length, bar height, past and future window, visibility,
  orientation, ready row side, skin, GCD style, seconds scale, and buttons to Reset position, the spell
  window and Options). The position is stored per Edit Mode layout, with a
  default for layouts that have none (schema 2).
- **The spell window** (`/actiontimeline config`) holds the spells, in the
  Cooldown Manager's layout: Timeline, Long cooldowns, Engine lanes, Not
  displayed. The sections are derived from the enabled, sink and long flags,
  never stored; a drop writes the flags and the order through the existing
  layered settings (ADR-0002), so nothing in the data model changes. Icons
  only, names in the tooltip, Revert to the layer as it was when the window
  opened.
- **Options** holds the rest, under section headers, with buttons to the
  other places and a dependent control.
- The frame is still not a registered Edit Mode system and writes nothing into
  Blizzard's layout tables; the panel is built from generic templates, never
  from `EditModeSetting*` or `CooldownViewerSettings*` templates whose mixins
  report to Blizzard's managers. Anything that calls
  Blizzard's Edit Mode manager from our code (opening Edit Mode, clearing its
  selection, stepping it aside) taints the raid frames' updates (probes E3
  and E6 failed in game, also through securecallfunction), so none of it is
  called: our panel and Blizzard's can both be open, and the panel has no
  Options button (a line points to `/actiontimeline options`). Post-hooks
  (`hooksecurefunc`) are fine.

## Consequences

- The Settings category loses seven controls; they live in the panel, which
  needs Edit Mode to reach (the spell window and Options say so).
- Changing a Blizzard-side detail (a kit name, a template) degrades to the
  plain look, never an error: every Blizzard template and atlas is guarded.
- Opening the spell window leaves Blizzard's own Edit Mode panel open.
