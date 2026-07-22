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

## [Unreleased]

### Unreleased (next build)

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
