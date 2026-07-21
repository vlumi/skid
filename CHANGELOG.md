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
