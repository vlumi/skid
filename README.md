# Skid

A top-down, drift-happy local-multiplayer racing game for Apple platforms — a
modern heir to keyboard-era couch racers like *Slicks 'n' Slide*, rebuilt
around controls that actually work on a phone.

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

Planned arc:

- **Phase 1 — local, one device.** Single-player (vs. AI) and 2–4 player
  same-screen, one thumb each. Find-the-fun first: prove the drift feels good
  before anything else is built.
- **Phase 2 — local network (no server).** Each player on their own device
  over MultipeerConnectivity — same-room, peer-to-peer, no accounts. A stretch
  goal is scaling this to many players.

## Principles

- **All graphics procedural** — cars, track, effects drawn in code; no image
  assets. (Carried from the author's other games.)
- **The same control scheme drives every mode** — single-player, local split,
  and networked all consume one input abstraction; a control scheme is just an
  input source. Several schemes are prototyped and swappable.
- **iOS first, Mac prepared-for.** The simulation and input are
  platform-agnostic from day one; only rendering/input-capture differ, so a Mac
  build (fun for local-network play) is a later target, not a rewrite.
- **English-only for now**, built on a String Catalog from day one so more
  languages are drop-in later.
- No server, no accounts, no tracking.

## Related

By the same author as [Donpa Squad](https://github.com/vlumi/donpa)
(Minesweeper) and Lattice Five (Morpion Solitaire); shares their engineering
discipline (pure testable core, XcodeGen, pinned lint/format, CI) but is a
**separate codebase** — patterns copied and adapted, never shared as a package.

## License

MIT (code).
