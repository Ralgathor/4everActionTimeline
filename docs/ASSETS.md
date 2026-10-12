# 4everActionTimeline — Asset List

Client-side art the timeline references, by atlas name or `Interface\` path.
Nothing here is shipped; every entry is referenced in-game (the policy line
is redistribution, not reference). Format and verification legend follow
4everSwingTimer's `docs/ASSET_LIBRARY.md`; entries shared with it point
there instead of being copied. Decisions about *how* these are used live in
`VISUAL.md`.

Verification legend:

- **source** — referenced by Blizzard's own UI code on the `forever` branch
  of `Gethe/wow-ui-source`; still run an atlas-exists check before first
  use, since the branch can lead or lag the client build.
- **shared** — already verified in play by 4everSwingTimer (see its asset
  library).
- **probed** — chosen during the probe session.

Probe 14 (2026-10-06, build 70235): every atlas in this file exists in game
(`C_Texture.GetAtlasInfo`, `PROBE_SESSION.md`). The runtime atlas guard
stays, since a later build can drop one.

## Native skin — track and now line

| Asset | Kind | Status | Use |
|---|---|---|---|
| `combattimeline-line-left` / `combattimeline-line-right` | atlas | source | Per-lane track line (Encounter Timeline track view). |
| `combattimeline-cooldown-divider` | atlas | source | Now line, stretched across every lane. |
| `combattimeline-pip` | atlas | source | Diamond at the now line's lane-start end. |
| `combattimeline-line-icontrail` | atlas | source | Motion trail on the next predicted mark (`ADD`). |

## Native skin — mark frame

| Asset | Kind | Status | Use |
|---|---|---|---|
| `UI-HUD-CoolDownManager-Mask` | atlas (mask) | source | Icon mask (Cooldown Manager / Encounter Timeline icons). |
| `UI-HUD-CoolDownManager-IconOverlay` | atlas | source | Icon frame overlay; overhangs the icon by a few pixels. |

## Native skin — bars and state overlays

| Asset | Kind | Status | Use |
|---|---|---|---|
| `UI-HUD-CoolDownManager-Bar` / `-Bar-BG` | atlas | source | GCD window bar fill and backing. |
| `combattimeline-fx-pause` / `-pause-icon` | atlas | source | Overlay on a paused hand's marks; in Single lane the icon alone, beside a paused hand's next diamond. |
| `combattimeline-fx-queued` | atlas | source | Overlay on the main-hand mark showing a queued ability. |
| `uitools-icon-chevron-right` | atlas | probed | Edge-clamp chevron (20×20, white, tinted to the track color; turned through tex coords per orientation). |

## Both skins — feedback

| Asset | Kind | Status | Use |
|---|---|---|---|
| `cast_standard_pipglow` | atlas | shared | Reposition pop, tinted teal / amber / red (`ADD`); in Single lane also the return ring on a ready-row slot or the now line, pale (`ADD`). |

## Flat skin

| Asset | Kind | Status | Use |
|---|---|---|---|
| `Interface\Buttons\WHITE8X8` | path | shared | Track lines, now line, borders, Flat trail streak. |

## Candidates noted, not chosen

- `combattimeline-line-break-mask` — Blizzard's track-line breaks (fixed
  intervals, at most three masks per texture); not drawn as of M7.
- `uitools-icon-chevron-left` — the right chevron turned through tex
  coords covers flipped orientations.

- `combattimeline-fx-highlight` / `-highlight-fx` / `-highlight-mask` —
  Blizzard's imminent-event highlight; rejected for the pop (pre-colored
  art tints muddy).
- `combattimeline-fx-queued-icon` — the queued overlay's icon variant;
  unused unless `fx-queued` alone reads weak.
- `UI-CooldownManager-OORshadow` — out-of-range shadow; out of v1.
