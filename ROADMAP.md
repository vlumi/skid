# Roadmap

The implementation plan, in milestone order. Versions are indicative, not
contractual, and this file is *expected to churn* — milestones get reshaped as
prototyping answers questions. Everything before 1.0 is beta by definition
(TestFlight from v0.1). As milestones ship, their detail moves to
`CHANGELOG.md` and this file keeps only open work. Settled rules, conventions,
and design decisions live in [AGENTS.md](AGENTS.md); this file is only *when*,
not *why*.

Guiding order: **the drift is the game.** Milestone one exists to answer "is
the driving fun?" and nothing that doesn't serve that question lands before it
is answered. Multiplayer-on-one-device is the product's heart, so it comes
right after the driving is proven; networking is deliberately last among the
features because deterministic lockstep is designed in from the first line of
the sim, not bolted on.

---

## v0.1.0 — One car, one track (is the drift fun?)

The deterministic sim, the first control scheme, and just enough rendering to
feel the driving. No race, no opponents, no menus.

**Scaffolding:**

- [x] XcodeGen `project.yml`: `SkidCore` package + `Sources/{iOS,Shared}`,
      thin iOS app target, bundle id `fi.misaki.skid`; the sim and input
      layers platform-agnostic so the later Mac target is drop-in
- [x] CI: pinned SwiftLint + swift-format (both `--strict`), `swift test`
      with coverage (view layer coverage-ignored), simulator build
- [x] String Catalog in place; every user-facing string localized from the
      first commit (English-only content)

**`SkidCore` (where nearly all v0.1 work and tests live):**

- [x] Fixed-timestep step function `advance(inputs:) -> newState`; seeded
      RNG; bit-for-bit determinism tests (same inputs → same race)
- [x] Hand-written arcade-drift car physics: heading, throttle along
      heading, grip < 1 so lateral velocity carries the car wide — grip /
      friction / turn-rate exposed as tunables
- [x] Track model: asphalt ribbon + grass, `surface(at:) -> Surface` with
      per-surface grip/drag modifiers; wall/kerb collision with bounce;
      layer-aware data model per AGENTS.md (the first track stays flat)
- [x] `ControlSource` protocol delivering car-relative `CarInput`

**Input & rendering:**

- [x] **Arcade touch-pad** scheme implemented; at least one more scheme
      stubbed so the swap seam is exercised
- [x] Procedural render: track with striped kerbs, one open-wheel buggy
      (body + four visible tires), fixed full-track camera
- [x] Skid marks: per-tire trails from slip + surface, persistent for the
      run — the feedback loop for tuning the drift

**Exit criteria:** drive laps by thumb and honestly answer "is this fun?"
Tuning notes recorded; go/no-go on the drift model (tight-grip fallback is
the plan B).

## v0.2.0 — Make it a race

- [x] Lap counting via ordered checkpoints (no shortcuts), start grid +
      countdown, finish + per-player race time
- [x] Remaining hazards as sim surfaces: **mud**, **water**, **oil slicks**
- [x] Marks extended: scuffed grass/mud trails; hazard-appropriate effects
- [x] Minimal HUD: lap and timing per player, in the style of the classics
- [x] Record every run as seed + input stream from the first lap-capable
      build (a replay/ghost is just that, per AGENTS.md — can't be
      retrofitted); playback lands later
- [x] Control-scheme A/B: two-zone tap-steer implemented, one-touch stub
      made real (the in-run switcher and virtual d-pad already landed with
      v0.1 device feedback)

## v0.3.0 — Couch multiplayer (the heart)

- [x] Multitouch routing: one touch per player, 2–4 per-player control
      zones that don't need to face the player
- [x] Car–car collisions in the sim (deterministic, hand-written), behind
      the per-race **contact / ghost** flag — ghost = pass-through,
      pure-speed racing; contact = the derby flavour
- [x] Per-player identity: body colours **picked by each player at race
      start**, grid slots, results screen
- [x] Split gas/steer two-thumb scheme (1–2 player layouts)

## v0.4.0 — Solo play: AI drivers & time trial

- [x] AI as just another `ControlSource`: racing line + steering toward it,
      rubber-banding-free difficulty via the same tunables as the player
- [x] Single-player vs. 1–3 AI; fill empty grid slots in multiplayer
- [x] Deterministic AI (seeded) so races stay reproducible in tests
- [x] **Time trial** mode + local hiscores per track (best lap, best race),
      persisted (versioned store) along with their replays
- [x] **Personal-best ghost**: translucent, non-interacting replay car to
      race against

## v0.5.0 — Content & polish

- [x] A small track set in the classic style (chicanes, a hairpin, hazard
      placement as track design); track picker (crossings arrive with the
      two-layer item below)
- [x] Two-layer tracks live: bridges as layered crossings (Overpass
      figure-8), ramps switching layers, jumps (airborne = ballistic,
      launching ramps ready for a jump track), bridge fall-off; occluded
      cars stay visible (ghost bubble, per AGENTS.md)
- [ ] Scheme A/B verdict: pick defaults, keep the winners, cut the losers
- [x] Sound + haptics: engine pitch, slides, collisions (procedural, no
      audio assets; toggles in setup/pause, persisted)
- [x] Minimal menus/settings — only what a couch session needs (setup
      screen + pause menu + sound/haptics toggles)
- [ ] **Release lane** (pulled forward from v1.0): `make release` —
      lock-step version/build bump, archive, TestFlight upload — plus
      `RELEASING.md`; **v0.5 ends with a TestFlight build**
- [ ] **App icon** (pulled forward from v1.0): generated from the game's
      own drawing code (`make icon`) — a drift scene, no image assets
      authored by hand

## v0.6.0 — Mac & physical controls

- [ ] macOS target (Universal Purchase, same bundle id), sim untouched —
      only render/input capture differ
- [ ] Keyboard scheme (arrows/WASD, 1–2 players) and GameController support
      as additional `ControlSource`s

## v0.7.0 — Local-network multiplayer

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

- [ ] Full replay viewer (watch/scrub any stored run — the data exists from
      v0.2); shareable ghost files between devices
- [ ] Track editor or procedural track variations
- [ ] Full vertical loops — the crazy one; only if the two-layer jump model
      proves fun (and readable) in play
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
