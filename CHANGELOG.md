# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- M7 skins and orientations: the Native skin (default) — Blizzard's
  timeline track segments, the cooldown-divider now line with its pip,
  Cooldown Manager–framed icons (mask and overlay, tinted red or amber for
  stopped casts and the held hand), the Cooldown Manager bar art for
  windows, the pause overlay on a paused hand's marks and the queued
  overlay on the main-hand mark — each element falling back to Flat when
  its art is missing; the four orientations (horizontal, horizontal
  flipped, vertical, vertical flipped) for lanes, windows, ticks, the edge
  clamp and its chevron, effects and the engine-drawn lanes; the motion
  trail on each lane's next predicted mark in its last 1.5 s. Skin and
  orientation in the Settings category; test mode shows a paused and a
  queued hand.
- M6 settings: the Settings category (visibility, windows, width, lane
  height and spacing, scale, lane background, hand / GCD / cast lane
  toggles, GCD length with custom value, engine-lane countdown), the lane
  window (`/actiontimeline config`: every class spell with enable, engine
  lane and manual cooldown, drag to reorder, class or character layer,
  overridden and new tags, reset to class), and placement in Edit Mode
  (drag handle, snap to Edit Mode frames, position saved per character).
- M5 engine-drawn sink lanes: opt-in per spell (up to 6, in lane order,
  grouped at the bottom), a transparent StatusBar fed the secret remaining
  cooldown every frame with the spell icon on its leading edge (far edge
  while longer than the window, at rest on the now line at zero), the
  optional engine countdown, and the spell lane dropping its calibrated
  prediction while its sink is on. `/actiontimeline sink`.
- M4 spell lanes. Curated data for all nine classes (starter sets, GCD
  references, linked and delayed-start cooldowns, resets, stance and form
  requirements); the lane set resolved through shipped defaults, class and
  player layers, each spell at its known rank. Spell lanes: happened marks,
  predicted ready marks (exact and full color from an out-of-combat read,
  desaturated from calibration), overdue until the engine reports ready,
  the ready, unusable (blue, grey, wrong stance or form) and
  unknown-cooldown marks, linked cooldowns, resets, delayed starts.
  Calibration: out-of-combat and combat-end reads, the learned cast offset,
  learned links, GCD-length rejection, stale flags (talent change, early
  cast, stuck overdue), login re-seed, pruning of retired ranks.
  `/actiontimeline lane`, `override` and `calibration [wipe]`.
- M3 cast and GCD lanes. Cast lane: every completed cast and instant (not
  auto-repeat shots, on-next-swing abilities or the Attack toggle), the
  in-flight cast's icon on the now line with a full-color completion mark
  from the live cast-time read (desaturated from the learned cast time if
  that read turns secret), pushback with an amber pop, red marks for
  stopped and interrupted casts (refused presses leave none), channels
  (red when stopped early). GCD lane: window bars opened only when the
  engine reports a GCD running (a per-class reference spell's isActive),
  1.5 s or 1.0 s for energy users, with an override setting.
- M2 hand lanes: main hand, off hand and ranged from LibClassicSwingTimerAPI
  (landings, the next landing, the cadence chain, overdue, parked and
  paused hands; weapon, druid-form and queued-ability icons; equipment-driven
  presence with per-hand settings). Hand-lane effects: reposition pops
  (teal, amber, red), correction streaks, the across-lane shake (honoring
  ShakeStrengthUI), clip ticks, the held amber border and delay spans,
  classified with 4everSwingTimer's rules. `/actiontimeline test effects`
  replays the swing-event signatures.
- M1 foundation: the event store with its secret guard (secret values are
  dropped and reported once after combat), the renderer (Flat skin,
  horizontal; pooled marks, ticks and window bars; edge clamp with
  chevron; overdue pin; visibility In combat / Always / Active), settings
  resolution over shipped defaults, the probe verdicts as `Probes.lua`, and
  `/actiontimeline test` (fake events showing the whole mark family) and
  `/actiontimeline perf`.
- Addon scaffold: the `4everActionTimeline.toc` manifest, `Core.lua`
  (versioned saved variables `FourEverActionTimelineDB` with the class and
  player layers, the LibClassicSwingTimerAPI gate that loads inert with a
  chat notice when the library is missing or older than MINOR 37, and the
  `/actiontimeline` slash command with `status` and `help`), `.pkgmeta`
  externals pinned to the library's v2.2.0 tag, `AGENTS.md` and `README.md`.
- `docs/PROBE_SESSION.md`: the in-game probe session script for probes
  1–15, run through SwingTestLog's new timeline probe commands, with
  the conservative default for each probe.
- Founding design in `docs/` (spec, visual design, asset list, research and
  probes 1–15, ADRs 0001–0004) and `GLOSSARY.md`.
