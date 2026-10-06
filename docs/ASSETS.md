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

## Native skin — track and now line

| Asset | Kind | Status | Use |
|---|---|---|---|
| `combattimeline-line-left` / `combattimeline-line-right` | atlas | source | Per-lane track line (Encounter Timeline track view). |
| `combattimeline-line-break-mask` | atlas (mask) | source | Breaks the track line where a mark sits. |
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
| `combattimeline-fx-pause` / `-pause-icon` | atlas | source | Overlay on a paused hand's marks. |
| `combattimeline-fx-queued` | atlas | source | Overlay on the main-hand mark showing a queued ability. |
| arrow / chevron (TBD) | atlas | probe 14 | Edge-clamp chevron; chosen by in-game atlas search. |

## Both skins — feedback

| Asset | Kind | Status | Use |
|---|---|---|---|
| `cast_standard_pipglow` | atlas | shared | Reposition pop, tinted teal / amber / red (`ADD`). |

## Flat skin

| Asset | Kind | Status | Use |
|---|---|---|---|
| `Interface\Buttons\WHITE8X8` | path | shared | Track lines, now line, borders, Flat trail streak. |

## Candidates noted, not chosen

- `combattimeline-fx-highlight` / `-highlight-fx` / `-highlight-mask` —
  Blizzard's imminent-event highlight; rejected for the pop (pre-colored
  art tints muddy).
- `combattimeline-fx-queued-icon` — the queued overlay's icon variant;
  unused unless `fx-queued` alone reads weak.
- `UI-CooldownManager-OORshadow` — out-of-range shadow; out of v1.
