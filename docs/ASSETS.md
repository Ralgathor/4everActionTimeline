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

Probe 14 (2026-10-06, build 70235): every atlas of the M7 set exists in
game (`C_Texture.GetAtlasInfo`, `PROBE_SESSION.md`); probe H1 (2026-10-12)
the cast bar's. The runtime atlas guard stays, since a later build can
drop one.

## Native skin — the bar (ADR-0006)

Native draws the whole bar in one family, Blizzard's cast bar
(`CastingBarFrameTemplates.xml`; chosen 2026-10-12 over the Cooldown
Manager bars of the timeline's Bars view):

| Asset | Kind | Status | Use |
|---|---|---|---|
| `ui-castingbar-background` | atlas | probed (H1) | The bar's body. |
| `ui-swingtimerbar-frame` | atlas | shared | The border, Blizzard's swing timer's, stretched over the bar whole (as 4everSwingTimer stretches it over its configurable bars): drawn for a bar of any size. It cannot be cut, so the now line crosses it. |
| `ui-castingbar-filling-standard` / `-filling-channel` | atlas | probed (H1) | A cast's and a channel's fill, in their own colors. Filling the bar's height, at its own proportions from the cast's start - a short cast shows its first part, cropped; a cast longer than the art stretches it - and revealed up to now as Blizzard's cast bar reveals its fill (drawn from the atlas's file, cropped by coordinates); the part still to run shows the rest of the art, faint. (Squeezed into the elapsed part it rescaled every frame and read oddly; tiling and its own height were tried, 2026-10-12.) |
| `ui-castingbar-pip` | atlas | probed (H1) | The now line: the cast bar's spark, `ADD`. |
| `ui-swingtimerbar-pip` | atlas | shared | A swing badge's stem across the bar: Blizzard's swing timer tick at its own width, stretched to the stem's length, tinted the hand's color. Flat, or missing, a 1 px line. |
| `cast_standard_pipglow` | atlas | shared | While a cast runs through the now line (not the Auto Shot windup, a plain fill): the glow Blizzard's cast bar trails behind its spark (37 x 12 on an 11 px bar, its end 2 px past the spark, `ADD`), scaled to the bar. |
| `cast_channel_pipshadow` | atlas | source, not yet seen in game | A channel's shadow at the spark instead (11 x 11, `BLEND`); missing, a channel shows none. |
| `UI-HUD-CoolDownManager-Bar` | atlas | source, seen in game (probe 14) | The GCD tint, tinted pale blue. |

## Native skin — fallbacks and glyphs

| Asset | Kind | Status | Use |
|---|---|---|---|
| `combattimeline-cooldown-divider` | atlas | source | The now line where the cast bar's spark is missing. |
| `combattimeline-pip` | atlas | source | The diamond at that now line's lane-start end. |
| `combattimeline-fx-pause-icon` | atlas | source | Beside a paused hand's next diamond. |
| `uitools-icon-chevron-right` | atlas | probed | Edge-clamp chevron (20×20, white; turned through tex coords per orientation). |

## Both skins — feedback

| Asset | Kind | Status | Use |
|---|---|---|---|
| `cast_standard_pipglow` | atlas | shared | Reposition pop, tinted teal / amber / red (`ADD`); and, only without `UI-HUD-ActionBar-GCD-Flipbook`, the return ring and an icon's urgency flash, pale (`ADD`). |
| `UI-HUD-ActionBar-GCD-Flipbook` | atlas | source (the Cooldown Manager's CooldownFlash), not yet seen in game | An icon's urgency flash at 1.5 s and a return's flash: 22 frames (11 rows of 2) over 0.75 s, additive at 1.35x the icon's size, one frame shown at a time. Missing, the pip glow above. |

## Flat skin

| Asset | Kind | Status | Use |
|---|---|---|---|
| `Interface\Buttons\WHITE8X8` | path | shared | The bar's body, border and fills, the now line and its steps, icon borders, the GCD (strip in both skins), the scale's ticks, the link badge, the correction streak. |

Not atlases:

- No link or chain atlas exists in the source: the linked-set mark is a
  small corner badge in `WHITE8X8`.
- The Auto Shot icon: the spell texture of spell 75
  (`C_Spell.GetSpellTexture`, file 132369, probe H3).

## Removed with ADR-0007

Referenced by Detailed and Single lane, which no longer exist:
`combattimeline-line-left` / `-line-right` (the per-lane track line),
`combattimeline-line-break-mask` (its line breaks),
`combattimeline-line-icontrail` (the motion trail),
`UI-HUD-CoolDownManager-Mask` and `-IconOverlay` (the framed icon),
`UI-HUD-CoolDownManager-Bar-BG` (the window bars' backing),
`combattimeline-fx-pause` and `combattimeline-fx-queued` (the icon
overlays).

## Candidates noted, not chosen

- `ui-castingbar-frame` (213 x 15, no slice data) as the border: drawn
  for an 11 px cast bar, it would not fit a bar of configurable width and
  height - stretched whole its rim thickened, nine-sliced or cut into pieces
  its ends missed the rails (2026-10-12/13).
- The Cooldown Manager bars (`UI-HUD-CoolDownManager-Bar-BG` placed as
  the timeline's Bars view places it, `-Bar` fills, the `-Bar-Pip`
  spark): one family with the icons, tried and set aside for the cast
  bar's look (2026-10-12).
- `uitools-icon-chevron-left` — the right chevron turned through tex
  coords covers flipped orientations.
- `combattimeline-fx-highlight` / `-highlight-fx` / `-highlight-mask` —
  Blizzard's imminent-event highlight; rejected for the pop (pre-colored
  art tints muddy; it drew a blank square, build 70235).
- `UI-CooldownManager-OORshadow` — out-of-range shadow; out of v1.
