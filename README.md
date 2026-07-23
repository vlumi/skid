# Skid

A top-down, drift-happy local-multiplayer racing game for Apple platforms — a
modern heir to the keyboard-era couch racers of the DOS days, rebuilt around
controls that actually work on a phone.

> **Status: prototyping.** "Skid" is a working repo name; the App Store name
> will be chosen (and researched) later. The first goal is only to find out
> whether the *driving* is fun — see [AGENTS.md](AGENTS.md).

## The idea

One track, fully visible on screen at once (static, centered — no scrolling).
Two to four players race on **one device**, each driving with **one thumb**.
Cars have momentum and slide through corners — the fun is in the drift, not in
precise lines. Controls are **relative to the car** (steer + throttle), so a
player's control zone doesn't need to face them — which is what lets several
people share a small screen.

Tracks are classic top-down circuits: a wide asphalt ribbon with striped
kerbs, grass everywhere off-track, and hazards on and around the racing line —
mud, water, oil slicks. Hard cornering burns rubber onto the asphalt, and
running wide leaves tracks in the grass. The cars are little buggy-style
open-wheelers — old-school F1 silhouettes with all four tires showing.

Planned arc:

- **Phase 1 — local, one device.** Single-player (vs. AI) and 2–4 player
  same-screen, one thumb each. Find-the-fun first: prove the drift feels good
  before anything else is built.
- **Phase 2 — local network (no server).** Each player on their own device
  over MultipeerConnectivity — same-room, peer-to-peer, no accounts. A stretch
  goal is scaling this to many players.

## Principles

- **All graphics procedural** — cars, track, effects drawn in code; no image
  assets.
- **The same control scheme drives every mode** — single-player, local split,
  and networked all consume one input abstraction; a control scheme is just an
  input source. Two schemes: **Casual** (aim where you want to go, the game
  handles the drift) and **Pro** (direct steer/throttle).
- **iOS first, Mac prepared-for.** The simulation and input are
  platform-agnostic from day one; only rendering/input-capture differ, so a Mac
  build (fun for local-network play) is a later target, not a rewrite.
- **English-only for now**, built on a String Catalog from day one so more
  languages are drop-in later.
- No server, no accounts, no tracking.

## Version history

High-level only — see [CHANGELOG.md](CHANGELOG.md) for the full detail and
[ROADMAP.md](ROADMAP.md) for what's next. Skid is in TestFlight beta.

- **v0.5.0 — Content & polish.** A track set + picker; two-layer tracks
  (Overpass figure-8, ramps, jumps, bridge fall-off, occlusion bubble);
  procedural sound + haptics; setup/pause menus; a data-driven track format
  (`TrackDesign` → compile → `Track`) with smoother corners; **aim-to-drive**
  controls; the `make release` lane + `make icon`; first TestFlight builds.
- **v0.4.0 — Solo play.** AI opponents (no rubber-banding), time trial,
  per-track hiscores, and a personal-best ghost.
- **v0.3.0 — Couch multiplayer.** 2–4 players on one device, per-player
  zones/colours, car–car contact vs. ghost racing.
- **v0.2.0 — Make it a race.** Checkpoints, countdown, timing, hazards, HUD,
  run recording.
- **v0.1.0 — One car, one track.** The deterministic drift sim, first control
  scheme, procedural rendering + skid marks. The drift proved fun.

## License

MIT. See [LICENSE](LICENSE).
