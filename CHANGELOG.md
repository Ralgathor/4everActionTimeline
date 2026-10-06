# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
