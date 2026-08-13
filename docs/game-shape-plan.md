# What the game is: modes, menu, and identity

## Why this exists

The racing works. The *game* around it is undesigned, and the current front end
says so plainly: one 351-line `SetupView` with every knob laid flat — mode,
player count, seating, AI count, difficulty, contact, track, colors — plus two
buttons that jump to the lobby and the editor. That is an engine control panel.
A player opening it is being asked to configure a simulation, not to choose
something to do.

The inventory makes the same point from another angle. Of **28** persisted
settings, **25 are developer tuning knobs** (`skid.sim.*`, `skid.aim.*`,
`skid.dpad.*`, and the editor/debug/elevation ones). Three are player settings:
haptics, sound, pace.

So this document is not a menu redesign. **The menu is the artifact that forces
the game's shape to be decided**, because a menu cannot be drawn without
answering what a player picks, in what order, and what persists between
sessions. Those answers are the game.

Nothing here is built yet, and nothing here should be built until the shape is
agreed.

## What exists today, honestly

Worth stating so the plan is sized against reality rather than memory.

**Solid:**

- Racing: drift model, AI, collisions, standings, laps, countdown.
- Couch multiplayer: up to four seats on one screen, side-by-side or
  face-to-face.
- Networked play: host-authoritative, multiple devices, lobby with join
  approval, leave and rematch.
- Track editor with a library, share codes, signing.
- Records **per track**: best race time, best lap, and a replayable ghost of the
  best race (`BestRecord`, `HiscoreBook`).
- Two modes: `race` and `timeTrial`.

**Absent:**

- Any notion of **who is playing**. No name, no profile, no per-player anything.
  Records are per *track*, so "best lap" belongs to the device rather than a
  person, and a couch of four people shares one set of numbers.
- Any structure **above one race**. A race ends, the result is shown, and it
  evaporates. No standings across races, no series, no reason the last twenty
  minutes happened.
- A **settings screen**. There are settings; there is nowhere to see them.
- Anything that distinguishes **single-player from couch** as a choice. Player
  count is a stepper on the setup panel.

## The shape being proposed

Three questions, in the order a player answers them.

### 1. Who is playing?

**Local profiles, on the device.** A name and a chosen car color, one per
person who plays on this phone. Not accounts, not sign-in, no server.

This is the keystone, and it is worth doing first even though it is not the most
visible: it is what makes every other item mean something. Records become *your*
records. A couch race has names in the standings instead of "P1". A tournament
has a leaderboard rather than four colors. Networked lobbies show who is there.

The cost is real but bounded: a `PlayerProfile` book on disk (the
`HiscoreBook`/`TrackLibraryBook` shape, already twice-proven), a picker at
launch, and threading an identity through the places that currently say `P1`.

**Open question:** whether records migrate to the first profile created, or
whether existing device records stay device-wide as "unclaimed". Migrating is
friendlier; unclaimed is honest. Leaning migrate, with the caveat noted in the
changelog.

### 2. Who are you playing with?

The top-level menu, and deliberately three entries rather than a player-count
stepper:

- **Solo** — one player against AI, or against the clock.
- **Couch** — two to four on this screen.
- **Nearby** — other devices (the existing lobby).

This is the split the current setup screen *hides*. A stepper from 1 to 4 makes
"playing alone" and "playing with three friends" the same act with a different
number, when they are the two different reasons someone opens the app.

Each one then asks only what it needs. Solo needs no seating layout. Nearby
already has its own lobby and does not need a local player count on the front
screen.

### 3. What are you playing?

The mode list, and the part that most needs deciding because two of the three
do not exist:

- **Single race** — exists. Pick a track, race it.
- **Time attack** — exists as `timeTrial`, and is the mode records already
  serve. Wants to be presented as a *chase*: your best, the ghost of it, and the
  gap. The pieces are all there and unsurfaced.
- **Tournament** — does not exist. A series of races over one or more sittings,
  with points and a standings table. This is the only genuinely new mode, and it
  is the one that gives a five-second lap a reason to be driven forty times.

**Tournament is the interesting question, and it needs its own decisions:**

- **How many races, and which tracks?** A fixed set, a random draw, or a
  player-chosen list. Leaning: pick a length (3/5/7), draw tracks from the
  library, allow re-draw before starting.
- **Points or cumulative time?** Points (a scoring table) forgive one bad race
  and keep a series alive; cumulative time is simpler and crueller. Leaning
  points, since the audience is a couch.
- **Does it survive quitting?** It must, or a five-race series on a phone is
  unfinishable. That means a persisted tournament state — small, but real.
- **Grid order between races.** Reverse-standings grids need this and are
  recorded in the roadmap as wanting a tournament layer. This is that layer.

## What this makes of the existing roadmap

Uncomfortable but worth saying: several things currently sitting in *next* are
decoration by this reading, and should move behind the items above.

- **Surfaces & hazards.** A lap is 2741–5141 units, which is 5–10 seconds.
  Surface variety on that is a change every second or so, on a track the player
  can see all of and will drive forty times — there is nothing to learn about a
  gravel patch visible from the start line. Authoring cost is real too: the
  clover is 47 pieces, so per-piece surface is 47 decisions per track. Parked,
  not deleted: a *whole-track* surface as part of a theme may still be worth it
  as a look, which is a much smaller feature.
- **Car color.** Parked already, and doubly so now: color becomes a *profile*
  property, so the picker is a consequence of identity rather than a feature of
  its own.

What stays regardless of this plan:

- **Facing legibility** (the accidental-reverse bug and the parked light cone) —
  a defect, not an addition.
- **The networking tail** — small, and finishes what players are already using.

## Sequence

Deliberately ordered so each step is usable on its own, and so the riskiest
design question (tournament rules) comes after there is something to hang it on.

1. **Profiles.** Name and color, stored on device, chosen at launch. Records
   become per-player. Standings show names.
2. **The menu.** Solo / Couch / Nearby, then mode, then track. The current setup
   panel's knobs split into *what this session is* (on the way in) and
   *settings* (their own screen). Developer tuning moves behind a debug section
   rather than sitting alongside player choices.
3. **Time attack, surfaced.** Your best, the ghost, the gap, the track's record
   list. Almost entirely presentation of data that already exists.
4. **Tournament.** The one new mode, with the rules decided above and persisted
   state so a series survives quitting.

Steps 1–3 are largely plumbing and presentation over things that exist. Step 4
is the new game.

## What this does not decide

- **Visual design.** Layout, type, color of the menus themselves. This document
  is structure only.
- **Career/unlocks.** The roadmap has a cosmetic-unlock ladder; it needs
  profiles and tournaments to exist first, and should be judged after.
- **Online anything** beyond the existing nearby play. No accounts, no server,
  no remote leaderboards.
- **Whether AI difficulty stays a per-race choice** or becomes a profile
  preference.
