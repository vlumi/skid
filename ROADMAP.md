# Roadmap

The implementation plan, in milestone order. Versions are indicative, not
contractual, and this file is *expected to churn* — milestones get reshaped as
prototyping answers questions. Everything before 1.0 is beta by definition
(TestFlight from v0.1). As milestones ship, they drop to the
[README version history](README.md#version-history) (brief) and
[CHANGELOG.md](CHANGELOG.md) (full), and this file keeps only open work.
Settled rules, conventions, and design decisions live in
[AGENTS.md](AGENTS.md); this file is only *when*, not *why*.

Guiding order: **the drift is the game.** Milestone one exists to answer "is
the driving fun?" and nothing that doesn't serve that question lands before it
is answered. Multiplayer-on-one-device is the product's heart, so it comes
right after the driving is proven; networking is deliberately last among the
features because deterministic lockstep is designed in from the first line of
the sim, not bolted on.

---

Shipped milestones (v0.1–v0.5) are summarized in the
[README version history](README.md#version-history); full detail is in
[CHANGELOG.md](CHANGELOG.md). This file keeps only open work.

## v0.5.x — Control feel (in progress)

The scheme A/B has a verdict: **aim-to-drive is the winner** — on touch it's
the only scheme that makes drifting accessible (manual countersteer needs
precision glass can't give). The remaining work is making it *feel* right,
then trimming the roster.

- [ ] **Aim-drift feel** — the big one. Aiming off-centre at speed should
      snap the car BODY toward the aim near-instantly and let the velocity
      correction come gradually (a real, holdable drift — see
      `aim-drift-feel` notes): a speed-scaled body-flip, handbrake-like on
      inertia but **no speed loss** (arcade). Turning currently too sluggish.
      Expose every plausibly-tunable parameter as a live in-game dial.
- [ ] Scheme roster cleanup: once aim-drift lands, decide which of the
      manual schemes (d-pad/slide/two-zone/one-touch/split) stay vs. cut,
      and set defaults.

## v0.6.0 — Track editor & shareable tracks

Hand-authoring track geometry hit its quality ceiling; a **phone-first**
editor with a small piece catalog is the answer, and its data becomes the
sharing format. Design settled (see `track-editor-piece-model` notes);
approach:

- [ ] **Piece model, headless first.** A track is an ordered ring of
      quantized catalog pieces (straight/curve{45,90}/bridge/ramp…), snapped
      **port-to-port** ("magnet", no real grid — a grid at most a cosmetic
      guide). Validity = every port mated + the loop closes; loose ends =
      unsaveable. Compiles to the runtime `Track`. Build + test as pure
      logic before any UI, **alongside** the free-form `TrackDesign` path
      (don't entangle it).
- [ ] **Phone-first editor UI** on top: tap-a-piece, tap-a-port, thumb-
      reachable palette, one-handed pan/zoom, no precision gestures. Must be
      genuinely usable on a phone, not a big-screen-only afterthought (iPad
      is an authoring convenience, not the design target).
- [ ] **Shareable tracks** — a track is a short list of piece ids, so it
      base64s into a reasonable URL.
- [ ] Wire editor output into track selection / the game.
- [ ] *Open, decide with the editor in hand:* whether built-ins migrate to
      the piece model (replace) or stay free-form `TrackDesign` (layer) —
      hinges on whether the catalog can rebuild Hairpin/Overpass well.

## v0.7.0 — Mac & physical controls

- [ ] macOS target (Universal Purchase, same bundle id), sim untouched —
      only render/input capture differ
- [ ] Keyboard scheme (arrows/WASD, 1–2 players) and GameController support
      as additional `ControlSource`s

## v0.8.0 — Local-network multiplayer

- [ ] Deterministic lockstep over **MultipeerConnectivity**: inputs-only
      sync, one peer as clock host, join/leave flow
- [ ] Cross-device play (iPhone/iPad/Mac in one room), no server
- [ ] Local network privacy strings + Bonjour service declarations
- [ ] Stretch: scale beyond 4 players (lockstep makes it reachable)

## v1.0.0 — The store release

- [ ] App name decided (with search); icon polish pass (light/dark/tinted
      variants — the base icon ships with v0.5)
- [ ] One ASC record (Universal Purchase), listing text + screenshots,
      privacy questionnaire (nothing collected)
- [ ] Submit, await review, release (release lane already live since
      v0.5)

## Backlog (unversioned)

- [ ] **Per-player control scheme**: let each player pick their own scheme
      at setup, instead of the current one global scheme for everyone. Each
      `PlayerControls` already owns an instance of every scheme; the
      selection would move from the shared `rig.scheme` to per-player, plus
      a setup UI.
- [ ] **Map themes**: whole-map looks beyond grass (sand/desert, snow, …).
      The track format already carries a `theme` field; the renderer learns
      it when the first non-grass theme lands.
- [ ] **Selective kerb striping**: red/white stripes only lining chosen
      corners' outer edges, plain white edges elsewhere — a per-corner
      `kerb` flag already in the track format; renderer support pending.
- [ ] Full replay viewer (watch/scrub any stored run — the data exists from
      v0.2); shareable ghost files between devices
- [ ] Full vertical loops — the crazy one; only if the two-layer jump model
      proves fun (and readable) in play
- [ ] Procedural track variations (the editor's piece catalog could seed
      these) — a maybe, not a commitment
- [ ] Damage/pickup mischief (dropped oil, turbo) — only if the core race
      wants more chaos
- [ ] Finnish/Japanese localization (String Catalog makes this
      translation-only)
- [ ] Spectator dressing: stands, trackside props, crowd texture
- [ ] **Local player profiles**: a chosen name at minimum, all on-device
      (no server accounts). Open question: allow ad-hoc anonymous players,
      or track everyone from the start by the name they chose?
- [ ] **Tournaments**: brackets/series across couch sessions, standings
      per profile
- [ ] **Career ladder** with cosmetic-only unlocks (liveries, effects) to
      show off when racing others — never performance
- [ ] **Different vehicles** — maybe; only if they stay balance-neutral
      (distinct look/feel, same competitive envelope)
- [ ] *(Parked)* **Portable profiles**: bring your profile to someone
      else's iPad and carry results home, cryptographically owned so nobody
      can claim your player. Unsolved: nothing stops the same profile
      "playing" on two devices at once — park it; may be moot once network
      play exists (your device is your identity)

## Deliberately out of scope

Per [AGENTS.md](AGENTS.md): no ads, no IAP, no accounts, no server, no global
leaderboards, no third-party runtime dependencies. Networked play is
peer-to-peer on the local network only. watchOS/visionOS/tvOS not targeted.
No performance tuning or upgrades — cosmetic unlocks only (see AGENTS.md for
the why).
