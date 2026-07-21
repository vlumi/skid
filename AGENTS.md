# Skid — agent & contributor guide

A top-down drift racer for Apple platforms; local multiplayer (2–4 on one
device), one thumb per player, static single-screen track. This file is the
canonical guidance for humans and AI agents. **The repo is at the prototyping
stage — the first job is to find out whether the driving is fun**, not to build
a finished game. Don't build menus, modes, or netcode before the core feel is
proven.

Separate project from its siblings [Donpa Squad](https://github.com/vlumi/donpa)
(Minesweeper) and Lattice Five (Morpion Solitaire). Reuse their *approach* by
copying and adapting, never by sharing a package.

## The one architectural rule everything hangs on

**A control scheme is an input source, not a game mode.** Every mode —
single-player vs. AI, local same-screen split, networked peer — produces the
same per-player, per-frame input value, which feeds one deterministic
simulation. Single-player uses the *same* scheme as multiplayer. Get this seam
right at line one:

```
protocol ControlSource { func input(for player: PlayerID, at tick: Tick) -> CarInput }
// CarInput is car-RELATIVE: steer (-1…1) + throttle (-1…1 or gas/brake), nothing screen-oriented.
// Touch zones, on-screen sticks, AI, keyboard, GameController, and network
// peers are all just ControlSources producing CarInput. The sim never knows
// which.
```

If input is modelled as data from the start, local play, AI, and (Phase 2)
networked play all compose instead of each being a rewrite.

## The simulation core (pure, deterministic, headless-tested)

Mirror Donpa's pure-core discipline:

- A **`SkidCore` Swift package** holds the car physics, track/collision, race
  state, and step function. **No SpriteKit, no SwiftUI, no I/O.** The step is
  `advance(inputs: [PlayerID: CarInput]) -> newState` at a **fixed timestep**.
- **Deterministic by construction** — same inputs → same state, bit-for-bit,
  because Phase 2's networking plan is **deterministic lockstep** (send only
  inputs, every device runs the identical sim). This is why the sim must NOT
  use `SKPhysicsBody` (SpriteKit physics isn't guaranteed deterministic across
  devices): write the car physics by hand — position, velocity, heading,
  lateral slip, wall bounce. For a top-down arcade racer that's small, and it
  keeps the many-player stretch goal reachable rather than needing a rewrite.
- Inject any randomness (seeded RNG) so races are reproducible in tests.

### Arcade-drift physics (the feel target)

The car has momentum and **slides**: steering rotates the heading, throttle
accelerates along the heading, but grip < 1 so lateral velocity carries the car
wide through a turn — the *Slicks 'n' Slide* drift. Tune grip / friction /
turn-rate for feel; this is where the effort goes and where the game lives or
dies. A tight/grippy model is the fallback if drift proves un-fun, but drift is
the point.

## Control schemes to prototype (swap freely against the same sim)

The first milestone is A/B-ing these to find the fun. First wired:
**arcade touch-pad**.

One-thumb (one touch per player → 4 players fit even on an iPhone's ~5-touch
limit; iPad ~11):

1. **Arcade touch-pad** *(first)* — thumb down = gas, horizontal offset from
   touch-start = steer, release = coast/brake. Simplest, most faithful.
2. **Analog virtual stick** — tilt-forward = throttle, left/right = steer,
   diagonals blend.
3. **Two-zone tap-steer** — hold anywhere = gas, left half = turn left, right
   half = turn right.
4. **One-touch** — permanent gas, tap = turn one way only. Radically simple;
   cheap to try.

Two-thumb (richer, fewer players per device):

5. **Split gas/steer** — one thumb throttle+brake, other thumb steer.

Non-touch (Mac-prep / controller path):

6. **Keyboard** (Mac) — arrows/WASD; the original's scheme, viable for 1–2.
7. **GameController** — stick + triggers; the "real couch" path.

## Platforms & phases

- **iOS first; Mac prepared-for** — sim + input are platform-agnostic; only
  rendering (procedural, Canvas or SpriteKit `SKShapeNode` — NOT SK physics)
  and input-capture differ. Mac is a later target (fun for local-network play),
  not a rewrite.
- **Phase 1:** local single-device — deterministic sim + static track +
  swappable one-thumb controls; single-player vs. AI and 2–4 same-screen.
  Ship-worthy on its own; the de-risking phase (is the driving fun?).
- **Phase 2:** local-network multiplayer over **MultipeerConnectivity** (no
  server, same-room), built as deterministic lockstep on the Phase-1 sim —
  exchange inputs, one peer as clock host. Stretch: scale to many players
  (lockstep's inputs-only sync is what makes that reachable).

## Conventions (carried from Donpa — apply once real code exists)

- **Toolchain:** Xcode + Swift 6, **XcodeGen** (`.xcodeproj` generated,
  gitignored, never committed; signing/team live only there).
- **Bundle id:** `fi.misaki.skid` (working). **Universal Purchase** from the
  start if it ships to both platforms. MIT, no monetization.
- **Localization:** English-only for now, but String Catalog + `Text(_,
  bundle:)` / `String(localized:)` from day one — never hardcoded literals.
- **Comments minimal**; determinism for tests (injected RNG, fixed timestep).
- **Lint/format/CI** (when set up): pinned SwiftLint + swift-format both
  `--strict`; CI runs lint + core tests (with coverage) + builds. Coverage-
  ignore the view layer; keep testable logic in `SkidCore`.
- **PRs:** branch off `main`, one focused change; `Co-Authored-By: <model>
  <noreply@anthropic.com>` trailer; a user-facing PR writes its own CHANGELOG
  bullet; wait for Codecov before merging.

## Deliberately out of scope

No ads, no microtransactions, no accounts, no server, no global leaderboards,
no third-party runtime dependencies. Networked play is peer-to-peer on the
local network only.

## First milestone (do this, nothing more)

One car, one static track, the deterministic arcade-drift sim, and a
`ControlSource` protocol with the **arcade touch-pad** implemented — plus at
least one more scheme stubbed so swapping is exercised early. Goal: drive one
car around and answer "is this fun?" No multiplayer, no AI, no menus, no
netcode yet.
