# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A live action timeline for WoW: Forever: one framed bar, read like a
  cast bar, with what you just did on one side of a now line and what is
  coming on the other. Things that happened are in full color; predictions
  are faded, so you can tell fact from forecast at a glance.
- Swings: your main hand and off hand as badges on the bar's edges - the
  equipped weapon's icon in the action bar button's frame, turned into a
  diamond - the next swing, the ones after it (smaller, dim) and past
  swings fading away. The next swing has a tick across the bar, Blizzard's
  swing timer pip, tinted to match the frame: the full bar's height, or
  half of it each when dual-wielding so the two never cross. Auto-attack
  off parks a dim badge beside the ready spells on the now line. Your
  ranged weapon stays a diamond (hollow). A queued ability such as Heroic
  Strike shows its icon on the bar at the swing it will ride.
- Auto Shot: the shot's windup, when you must stand still, is drawn as a
  teal cast ending at the Auto Shot icon. Moving holds the shot back: its
  icon turns amber and an amber line shows the delay.
- Swing timing feedback: a swing that lands early, a parry speed-up, or a
  swing reset by a cast or a weapon swap flashes and moves the next swing
  at once, so you see the change. A landing flashes the landed badge at the
  swing, in the badge's own turned shape. Respects the game's screen shake
  setting.
- Casts and channels fill the bar in gold and green, the spell's icon at
  the end. An interrupted or failed cast keeps a red border; pushback
  moves the end.
- The global cooldown as a blue tint over the bar, or as a strip along
  its edge.
- Spell cooldowns: each tracked spell's icon rides the bar toward the now
  line and flashes once when it is one global cooldown away. Spells you can
  press now stay on the now line, stacked: the ones you can use in front,
  then those tinted blue (you lack the resource) or grey (unusable), three
  at a time; using one makes it burst out of the stack, and the others
  slide into place. Or turn the stack off and let the
  Cooldown Manager show them: a returning spell then flashes on the now
  line. Long cooldowns (30 s or more) never stack and flash on the now line
  when they return. Icons that would overlap stack,
  three at a time, with "+n" for the rest; spells sharing a cooldown show
  as one icon with a small link mark.
- Cooldowns are learned: cast each tracked spell once out of combat.
  `/actiontimeline calibration` shows what is known, and
  `/actiontimeline override` sets a cooldown by hand. Starting spell sets
  for all nine classes; Warrior, Rogue and Paladin are checked in game.
- Engine lanes (`/actiontimeline sink`, up to 6 spells): a thin row under
  the bar where the game itself places the spell's icon, exact even in
  combat, with its own countdown if you want it.
- Your spell list in `/actiontimeline config`, laid out like the Cooldown
  Manager's: spells as icons in four sections - Timeline, Long cooldowns,
  Engine lanes, Not displayed - dragged to reorder or move between them,
  a right-click menu for a manual cooldown, a search box, and Revert. For
  your whole class or this character only.
- Edit Mode: the timeline moves like Blizzard's own frames (their
  highlight, snapping to other frames and to the grid, with the red snap lines while you drag), keeps a position for each Edit
  Mode layout, and a click opens its panel: scale, opacity, length, bar
  height, past and future window, engine lane gap, when it shows, four orientations, the ready spells, the skin,
  the global cooldown style and the seconds scale.
- Settings (Options > AddOns, or `/actiontimeline options`): the global
  cooldown length, which swing and cast lanes to show, and the engine lane
  countdown, with a button to the spell list.
- `/actiontimeline test` shows every kind of mark on a running clock, and
  `/actiontimeline test effects` replays the swing timing feedback.
- If the game hides a value the timeline needs, the event is skipped and
  reported once in chat after combat; nothing is guessed.
