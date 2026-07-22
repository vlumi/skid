# Changelog

All notable changes to Skid are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Grouped by **marketing version** (a roadmap milestone), then by **build
number** within it — the version stays steady while the build climbs each
TestFlight upload. Each version's top section, **Unreleased (next build)**,
collects entries merged to `main` but not yet in a TestFlight build; cutting a
release renames it to that build's heading and opens a fresh empty one. A
user-facing PR writes its own bullet here (see [AGENTS.md](AGENTS.md)).

## v0.5.0

### Unreleased (next build)

- A **Tuning** panel in the pause menu, for finding the feel on real
  thumbs: d-pad dead zone, travel, steps (including full analog), and a
  response **curve** (softer near the center for smoother small
  corrections) — all applied live mid-race — plus a **Pace** dial that
  slows acceleration and top speed for learning (agility stays; applies
  on Reset, and slowed runs never touch your hiscores). All remembered
  across launches.
- **Sound**, all synthesized live (no audio files, like the graphics):
  an engine note that climbs with your speed, tire noise when you slide,
  and thumps when you hit walls or each other. Respects the silent
  switch and mixes politely with your own music.
- **Haptics**: taps for impacts (harder hit, harder tap) and a success
  buzz when you take the flag.
- Sound and haptics toggles in the pause menu, remembered across
  launches.

- **Overpass** — the figure-eight, and the two-layer system it rides on:
  yellow-striped ramps lift you onto a **bridge** over the crossing (with
  its own checkpoint — the overpass must be driven, not dodged), stray
  off the edge and you drop back down. Cars under the bridge show
  through as a colored bubble so nobody ever loses their car. Jump
  ramps (full ballistic flight, no steering mid-air) are in the engine,
  waiting for a track that dares to use them.

- **Two new tracks**, picked on the setup screen: **Gauntlet** — the
  rectangle pinched on both straights, narrower road, mud filling the
  bottom chicane — and **Hairpin** — a fast bowl feeding a tight 180°
  peninsula with its own checkpoint at the apex. Hiscores, ghosts, and
  time trial are all per-track. Every built-in track has to prove an AI
  can lap it before it ships.

- Race chrome that stays out of the way: each player's lap/time chip now
  lives in their **own corner, facing them** (rotated for players across
  the table), the countdown shows both ways in face-to-face games, and
  the in-race buttons are gone — one small **pause** button on the center
  seam opens a menu (resume / scheme / reset / setup) and actually
  freezes the race. System edge swipes now need the deliberate
  double-swipe, so a thumb at the edge doesn't summon Control Center
  mid-corner.

- **AI drivers**: fill the grid with up to 3 opponents from the setup
  screen. They drive the same cars with the same physics (no
  rubber-banding — a skill ladder of lookahead/caution instead), follow
  the racing line, drift the corners, and recover when they hit a wall.
- **Time trial**: lap forever against the clock — live lap timer,
  session best, and your all-time **best lap** and **best race** are now
  saved per track (survives relaunch). The best race also stores its
  full replay…
- **Personal-best ghost**: …which drives alongside you in time trial as
  a translucent ghost car — race your own record. Never collides, never
  leaves marks.
- **Seating options**: 2-player picks side-by-side or face-to-face;
  3-player picks which corner of the screen stays open — controls always
  face the player.

- **Couch multiplayer**: 2–4 players on one device, one thumb each. A
  setup screen picks player count, per-player car colors (tap to cycle),
  and **Contact** (cars bump — derby chaos) vs **Ghost** (pass through —
  pure speed) before each race. Every player gets their own control zone
  (halves for two, quadrants for four — the top row's controls face
  players sitting across the table), outlined in their color; touches
  are routed by where they start, so thumbs never steal each other's
  cars. Per-player lap chips in the HUD, next-checkpoint dots per player,
  and a results card with standings and best laps when everyone's done.
- New **Split** two-thumb scheme in the switcher: one thumb gas/brake,
  the other steer, both in quantized steps.

- Checkpoints you can see and can't unfairly miss: gates now span the
  whole corridor (running wide over grass still counts — the grass is the
  penalty), only gross cuts through the infield don't. Each checkpoint is
  drawn like a physical gate — a faint line with a post at each road edge —
  and a dot in **your car's color** lights up beside your next gate's
  posts (each player gets their own dots); the start/finish keeps its
  checkers.
- It's a race now: three laps against the clock — 3-2-1-GO countdown
  holding the car on the grid, lap counting through ordered directional
  checkpoints (cutting the track or driving backwards never counts), and
  a lap/time HUD with your best lap. After the flag the car rolls out and
  the final time stays up; Reset starts a fresh race.
- Hazards on the racing line: a mud bog pinching the bottom straight, a
  water pool clipping the top-right exit, and an oil slick on the right
  straight — each with its own grip/drag feel, and mud/water print tire
  trails back onto the asphalt for a while after you drive through.
- Every run is now recorded as seed + input stream (tiny, deterministic)
  — the raw material for future replays, ghosts, and hiscores.
- Two more control schemes in the switcher: **Two-zone** (hold = gas,
  half of the screen picks the turn) and a real **One-touch** (permanent
  gas; hold = turn, quick tap = flip turning direction).
- Smooth marks on small phones: skid marks now render as a few batched
  strokes instead of one per segment (choppy on iPhone 13 mini once they
  piled up), record at half tick rate, and keep a smaller budget — oldest
  marks still fade out first. D-pad gets a third step per axis for finer
  throttle/steer modulation.
- Controls, round two (first on-device feedback): a **virtual d-pad** is
  the new default — it appears where the thumb lands (within the player's
  control zone, tinted the car's color), steers while coasting, and
  quantizes each axis to half/full steps instead of binary or full-analog;
  pull back to brake/reverse. A button next to Reset switches schemes
  in-run (D-pad / Slide / One-touch) for A/B on the device.
- First drivable prototype: one car, one track, thumb-driven — drive laps
  with the arcade touch-pad (thumb down = gas, slide sideways = steer,
  release = coast) and feel the drift. Skid marks burn onto the asphalt in
  hard slides and scuff the grass when you run wide.
- Project scaffolding: XcodeGen project (iOS target), `SkidCore` package
  with the deterministic fixed-timestep drift sim (surfaces, layer-aware
  track model, checkpoint gates, wall bounce) and its tests, pinned
  lint/format tooling, and CI (lint, tests + coverage, simulator build).
