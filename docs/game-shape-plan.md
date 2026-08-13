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

**Guests by default; a profile is an upgrade.** Anyone can race immediately as
"P2" with no name and no setup. Making a profile — a name and a chosen car color,
stored on this device — is what buys you *kept* results.

That order matters more than it looks. Profiles-first would put a text field in
front of the thing people opened the app for, and a couch guest who just wants a
turn should never have to register to take one. So:

- **A guest races normally.** Same cars, same modes, same tournaments.
- **A guest's times are not recorded.** Nothing to attach them to, and inventing
  a slot for "whoever was in seat 2 that time" is worse than not keeping it.
- **A profile keeps its records**, shows its name in standings, and carries its
  color preference between sessions.
- **Mixed seats are ordinary** — one person with a profile, a visiting friend as
  a guest, in the same race.

This also settles the migration question that was open here: existing device
records become the **first profile's**, because today's records were made by
whoever owns the phone. Guests never inherit them, and never write to them.

Not accounts, not sign-in, no server. The cost is bounded: a `PlayerProfile` book
on disk (the `HiscoreBook`/`TrackLibraryBook` shape, already twice-proven), a
seat-to-identity mapping, and threading it through the places that say `P1`.

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

## The library is the dependency nobody scheduled

**A tournament is a sequence of tracks, so it is only as good as the tracks it can
draw from.** Five races on four built-ins means repeats in every series, and no
scoring rule fixes that. This is the constraint that decides how good the mode
feels, and it is not a coding problem.

The honest position: **the engine is not the limit — the designs are.** The
catalog already offers three straights, 45° and 90° curves at tight/medium/sweep
radii, hairpins in three radii, fitters for shapes the catalog cannot make, plus
elevation, crossings and railings. Four tracks have been designed with all of
that. So "build the best library" is mostly **sitting in the editor and designing
tracks**, which is authorship rather than engineering.

What engineering can do for it, in order of value:

1. **Make the built-in set big enough to draw from.** A tournament wants enough
   variety that a 5-race series rarely repeats — call it 8–12 tracks. They are
   share codes in `TrackLibrary.builtins`, so each one costs a design session and
   two lines of code. Nothing to build first.
2. **Make them differ in the ways that matter.** Track *identity* comes from lap
   length, corner mix, and whether it climbs — not from surface or decoration. A
   good set spans short/technical to long/fast, with a couple of elevated ones.
   Worth writing down as a target so the set is deliberate rather than whatever
   got made.
3. **Curation over quantity.** A tournament drawing from tracks the player half
   finished in the editor would be a bad series. So the draw pool needs a notion
   of *raceable and worth racing* — the library already knows raceable; "worth
   racing" is what the built-in flag means.

**Decoration earns its place here, and only here.** Bare tracks look unfinished,
and a library of a dozen of them looks more unfinished still — the same asphalt
ribbon on green, twelve times. So *some* scenery before 1.0 is justified, on the
grounds of making a library look like a set of places rather than a set of
diagrams. That is a much narrower claim than the parked content work: it is about
the tracks having character, not about the driving changing.

Deliberately still parked, per the decision recorded below: hazards, per-piece
surfaces, themes, and further decals.

## Parked until the game is more finished

**Decision: all track-content work stops here.** Not deleted, not
in-progress-and-deprioritized — parked, with one narrow exception. The pattern
worth naming is that each of these is cheap to *build* and unproven to *matter*,
and "the sim half is already done" kept being mistaken for a reason to do it.

- **Hazards** (oil, water, mud as placeable things).
- **Per-piece road surface** (gravel, snow, dirt). A lap is 2741–5141 units, so
  5–10 seconds, on a track the player sees all of and drives forty times; surface
  variety at that scale is a change every second with nothing to learn about it,
  and 47 authoring decisions on the clover.
- **Off-road surface and themes** (snow/sand/dirt ground).
- **Further decals** beyond what exists.
- **Car color as a feature.** Parked already, and now redundant: color becomes a
  *profile* property, so a picker is a consequence of identity.

**The one exception: some decoration before 1.0.** Justified by the library
argument above rather than by gameplay — a dozen tracks that are all asphalt on
green read as a set of diagrams, not places. Scope it as *making tracks look
alive*, not as changing how they drive, and it does not need surfaces, themes or
hazards to do that.

What stays regardless of this plan:

- **Facing legibility** (the accidental-reverse bug and the parked light cone) —
  a defect, not an addition.
- **The networking tail** — small, and finishes what players are already using.

## Sequence

Deliberately ordered so each step is usable on its own, and so the riskiest
design question (tournament rules) comes after there is something to hang it on.

1. **Profiles, with guests as the default.** A seat is a guest unless a profile is
   chosen; a profile is a name and a color, stored on device. Records become
   per-player, and guests record nothing. Standings show names.
2. **The menu.** Solo / Couch / Nearby, then mode, then track. The current setup
   panel's knobs split into *what this session is* (on the way in) and
   *settings* (their own screen). Developer tuning moves behind a debug section
   rather than sitting alongside player choices.
3. **Time attack, surfaced.** Your best, the ghost, the gap, the track's record
   list. Almost entirely presentation of data that already exists.
4. **Grow the built-in library** — 8–12 tracks spanning short/technical to
   long/fast, some elevated. Authorship rather than engineering, and it can run in
   parallel with any of the above: each track is a design session and two lines in
   `TrackLibrary.builtins`. **Before tournaments**, since a series drawing from four
   tracks repeats itself no matter how the scoring works.
5. **Tournament.** The one new mode, with the rules decided above and persisted
   state so a series survives quitting.

Steps 1–3 are largely plumbing and presentation over things that exist. Step 4 is
authorship, needs no code, and can start today. Step 5 is the new game — and is the
only one that should wait for the others.

## What this does not decide

- **Visual design.** Layout, type, color of the menus themselves. This document
  is structure only.
- **What "decoration" is**, concretely — which props, how they are placed, whether
  they are anchored to pieces. Only that *some* is wanted before 1.0, for the
  library's sake, and that it must not drag surfaces or themes in with it.
- **The target track set**, track by track. The 8–12 count and the
  short/technical-to-long/fast span are a target, not a list.
- **Career/unlocks.** The roadmap has a cosmetic-unlock ladder; it needs
  profiles and tournaments to exist first, and should be judged after.
- **Online anything** beyond the existing nearby play. No accounts, no server,
  no remote leaderboards.
- **Whether AI difficulty stays a per-race choice** or becomes a profile
  preference.
