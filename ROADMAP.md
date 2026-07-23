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

### v0.5.x — Couch layout & readability polish

The couch redesign (controls as bands beside a clear map) and the random
starting grid have shipped; these are the follow-ups they surfaced. Small,
mostly view-layer, no sim risk.

- [ ] **Car readability, background-independent** — cars need to stand out on
      any surface (map themes are coming, so no fixed palette can). Add an
      **outline / drop-shadow / halo** per car in `draw(car:)`
      (`TrackRenderer+Cars.swift`), not a palette retune. Yellow-on-grey is
      the current worst case.
- [ ] **Heading indicator → headlight cone** — replace the bold projected
      arrow with a soft cone in the player's tint, projected ahead (same
      `draw(car:)`). The arrow shouts now that the body-flip is calmer.
- [ ] **Finish is unmistakable + splits in the band** — on finish, show the
      player's lap times in their control band (a clear "done, here are your
      splits" state). Fixes players stopping early, unsure they'd finished.
      Lives in `RaceHUD.playerChip` / the band area.
- [ ] **Per-player position, folded into the lap chip** — show each player's
      current race position (P1/P2/…) **together with the lap info** in their
      existing chip (e.g. "P2 · Lap 2/3"), which already rides the clear
      map-side edge of the band — off the thumb (mid/outer, where the stick
      lands) and out of the notch (safe-area-clamped), rotated for far
      players. One combined chip, one place, reuses `RaceHUD.playerChip`; do
      it with the finish-splits work. **Ranking:** deterministic off `Race`
      state — laps, then gates passed this lap, then shortest distance to the
      next gate (true on-track order). **Cadence:** recompute continuously but
      **debounce** so near-ties don't flicker the number. This is the
      per-player take on "live standings" and **removes the need** for a
      separate shared top-area element.
- [ ] *Spec gap — shared pause placement.* Pause sits at the map's
      bottom-centre seam; on some seatings that's awkward. With position now
      folded into each player's chip (above), the top area no longer competes
      for it — but the seam placement per seating still wants a look.

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
- [ ] **Content convention: taller track aspect.** All maps get redrawn in
      the editor; author them ~**1.2:1** (e.g. ~1600×1333) instead of today's
      1.6:1, so the map is ~⅓ bigger on the smallest phone while still leaving
      ≥132pt control bands. Engine is already aspect-agnostic (`fittedMapRect`
      + the couch bands adapt) — this is purely an authoring choice, nothing
      to build, but it belongs with the editor since that's where maps are made.
- [ ] **Catalog beyond road pieces — decorations.** On-road arrows, trees,
      buildings, walls (scenery + directional markers, not just track
      segments). Placed in the editor.
- [ ] **Gates at seams only.** A gate anchors to the boundary between two
      pieces (a port), not mid-segment — fits the port-graph model and
      simplifies gate anchoring vs. today's node+t scheme.
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
