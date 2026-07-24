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

## v0.6.0 — Track editor & shareable tracks

Hand-authoring track geometry hit its quality ceiling; a **phone-first**
editor with a small piece catalog is the answer, and its data becomes the
sharing format. Design settled — see [docs/track-pieces.md](docs/track-pieces.md);
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
      base64s into a short URL at `skid.misaki.fi/t/<code>`. Hard goal: **any
      design fits in a scannable QR code** (budget table in the design doc —
      keep it honest as encoding sections are added).
- [ ] Wire editor output into track selection / the game.
- [ ] *Open, decide with the editor in hand:* whether built-ins migrate to
      the piece model (replace) or stay free-form `TrackDesign` (layer) —
      hinges on whether the catalog can rebuild Hairpin/Overpass well.
- [ ] **Content convention: taller track aspect.** All maps get redrawn in
      the editor; author them ~**1.2:1** (e.g. ~1600×1333) instead of today's
      1.6:1, so the map is ~⅓ bigger on the smallest phone while still leaving
      ≥132pt control bands. Engine is already aspect-agnostic (`fittedMapRect`
      + the couch bands adapt) — this is purely an authoring choice, nothing
      to build, but it belongs with the editor since that's where maps are made.
- [ ] **Catalog beyond road pieces — decorations.** On-road arrows, trees,
      buildings, walls (scenery + directional markers, not just track
      segments). Placed in the editor.
- [ ] **Gates at seams only, editor-marked.** A gate anchors to the boundary
      between two pieces (a port), not mid-segment; the author marks which
      seams count (start/finish fixed at seam 0, up to 16 gates total).
- [ ] **Rougher hazard shapes + surface textures.** Water/oil/mud shouldn't
      be perfect circles — rotatable, combinable blobs. Plus textures for most
      surfaces eventually (grass, mud); asphalt stays plain grey. Rendering
      polish, lands alongside the decorations catalog.

## v0.7.0 — Mac, physical controls & orientation

Clusters the "big screen + orientation" work: Mac, iPad's larger canvas, and
landscape all share the same layout/orientation machinery, and the `mapRect`
indirection from the couch redesign keeps them localized.

- [ ] macOS target (Universal Purchase, same bundle id), sim untouched —
      only render/input capture differ
- [ ] Keyboard scheme (arrows/WASD, 1–2 players) and GameController support
      as additional `ControlSource`s
- [ ] **Landscape mode (couch).** Turn the phone and the *whole game*
      reorients 90° — map, HUD, and each player's control/steering frame —
      but the touch **zones stay pinned to the same physical device regions**
      (thumbs don't move; zones are device-space, not UI-space). Payoff: wide
      tracks align with the long axis → bigger map. **Lock orientation during
      a race** (settle it before the race, freeze it — a mid-drift flip is
      chaos); unlock in menus.
- [ ] **iPad & landscape map-sizing policy.** Grow `fittedMapRect` from pure
      edge-to-edge fit into a policy: phone = fit-to-width (current); **iPad =
      cap the map at a comfortable size and reserve *more* for controls** (big
      screen ≠ giant map, map floats with margins); **landscape = bands dock
      left/right** of the map (free space is on the sides), which needs
      `CouchRig` side-band support (today it only does top/bottom).

## v0.8.0 — Local-network multiplayer

- [ ] Deterministic lockstep over **MultipeerConnectivity**: inputs-only
      sync, one peer as clock host, join/leave flow
- [ ] Cross-device play (iPhone/iPad/Mac in one room), no server
- [ ] Local network privacy strings + Bonjour service declarations
- [ ] Stretch: scale beyond 4 players (lockstep makes it reachable)
- [ ] **Decide pause semantics for networked play.** The couch map-tap pause
      freezes one device; under lockstep that's a whole different problem
      (whose tap freezes everyone? re-sync on resume?). Likely: no free pause
      in a networked race (or a vote/host-only pause). Decide here, not in the
      couch code.

## v1.0.0 — The store release

- [ ] **Final polish & balancing pass.** With all content and controls
      settled, do the tuning that only makes sense at the end: **bake the
      final control-feel dials** (the aim-drift model + defaults shipped in
      v0.5; the live dials let this wait), **balance** the tracks / AI /
      difficulty, and sweep the remaining rough edges. This is why the
      control-feel tune was deferred here.
- [ ] Icon polish pass (light/dark/tinted variants — the base icon ships with
      v0.5). App name is settled: **Skid Jam**.
- [ ] One ASC record (Universal Purchase), listing text + screenshots,
      privacy questionnaire (nothing collected)
- [ ] Submit, await review, release (release lane already live since
      v0.5)

## Backlog (unversioned)

- [ ] **Pause-menu cleanup** (with per-player scheme change). The pause menu
      wants a rethink; fold in a way to change each player's scheme mid-race
      (setup-time per-player selection already shipped — this is the in-race
      counterpart, deferred out of that PR on purpose).
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
      per profile. *Would unlock* a **reverse-standings starting grid** (race
      N grid = reverse of standings after N−1, worst on pole; ties broken by
      the seeded RNG) — blocked today for lack of any persistent cross-race
      standings layer.
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
