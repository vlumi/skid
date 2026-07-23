# Skid — agent & contributor guide

A top-down drift racer for Apple platforms; local multiplayer (2–4 on one
device), one thumb per player, static single-screen track. This file is the
canonical guidance for humans and AI agents. **The repo is at the prototyping
stage — the first job is to find out whether the driving is fun**, not to build
a finished game. Don't build menus, modes, or netcode before the core feel is
proven.

The repo is fully independent and self-contained: it shares no code or
packages with any other project.

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

The discipline:

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
wide through a turn — the classic top-down-racer drift. Tune grip / friction /
turn-rate for feel; this is where the effort goes and where the game lives or
dies. A tight/grippy model is the fallback if drift proves un-fun, but drift is
the point.

## Track & surfaces (sim data, not decoration)

The look to aim for is the classic top-down circuit: a wide asphalt ribbon
with red/white-striped kerb edging, the whole track on screen at once, grass
filling everything off-track; crossings/bridges and spectator dressing can
come later. Surfaces are **part of the simulation**, not just rendering — the
track model answers `surface(at: Point) -> Surface` deterministically, and the
step function applies each surface's grip/drag modifiers:

- **Asphalt** — baseline grip, no drag.
- **Grass** (all off-track ground) — reduced grip plus drag; running wide is
  survivable but costs speed.
- **Mud** — heavy drag, low grip; a bog to avoid.
- **Water** — low grip and strong drag; puddles punish the racing line.
- **Oil slick** — near-zero grip patch on the asphalt; momentum carries the
  car straight through while steering does almost nothing.

Exact modifier values are feel-tuning, like the drift itself. Track edges are
walls/kerbs handled by the hand-written collision (bounce), not a surface.

### Checkpoints (a lap must be earned)

Every track carries an **ordered sequence of directional checkpoint gates**,
and a lap counts only when all of them are crossed in order, in the driving
direction, before the finish line. Checkpoints are sim data on the track
model, evaluated deterministically per tick like everything else; wrong-way
driving simply fails to advance the sequence.

Gates are **forgiving by design** (first device trial: ribbon-width gates
made laps impossible to earn when running wide): each spans the whole
corridor — from a modest reach into the infield out to the boundary — so
cutting across grass still counts; grass *is* the penalty (drag + low grip).
Gates exist to kill gross shortcuts only, like circling near the start line
or lapping the infield center.

Checkpoints are **visible, drawn like physical gates**: a faint line across
the asphalt (its on-ribbon part — `Track.ribbonSpan(of:)`) with a **post at
each ribbon edge**, slalom-style. Next-gate guidance is **per player**: a
dot in each car's color lights up beside the posts of that player's next
gate — honest with 2–4 players on one screen, where a single global
highlight would lie. The start/finish keeps its checkered line. Track
*design* owns the rest: any future ramp/jump placement has to be checked
against the gate sequence so a flight can't bypass one.

### Height: two layers, ramps, jumps (design the seam, build it later)

Tracks may cross themselves, so the track model is **two-layer** (ground +
elevated) from the start: every track segment/wall carries a layer, the car
carries a current layer, and `surface(at:)` and collision are asked per-layer
— cars and walls on different layers don't interact. Bridges and tunnels are
then just overlapping segments on different layers; short **ramps** switch
the car's layer; a ramp taken fast enough becomes a **jump** — a brief
airborne ballistic state (no grip, no steering, no surface drag) until
landing. **Implemented (v0.5)**: centerline segments carry layers
(`elevatedSegments`), `Ramp` lines switch the car's layer (crossed forward
= up, backward = down; `launches` throws the car ballistic, flight scaled
by speed — `CarTuning.jumpTicksPerSpeed`), and a grounded elevated car that
strays off its ribbon **falls off the bridge** (short drop, back to
ground). Airborne = no steering/throttle/grip/drag until landing; airborne
cars don't collide. Gates and the AI's line anchor are layer-aware. Full
vertical loops remain a backlog curiosity, not designed for.

Rendering rule: **a car is never invisible.** Implemented as the bubble
variant: a car under the bridge shows through as a semi-transparent bubble
in its color tracking its position. Bridges draw with a drop shadow
(trimmed clear of the ramp mouths) and a lighter, butt-capped deck; ramps
render as **gradient slope wedges** (road-gray climbing to deck-gray,
retaining-wall edges, chevrons along the driving direction); airborne cars
draw scaled up with a ground shadow; marks only ever print on the ground
layer. Pure rendering; the sim knows nothing of it.

### Marks on the ground (cheap, high-value feedback)

Hard lateral slip on asphalt burns rubber; driving over grass or mud scuffs
it. Marks are per-tire trails that persist for the whole race and are **pure
rendering**: derived from sim state (slip above a threshold + current
surface), accumulated into a draw layer, never fed back into physics. Wire
skid marks up early — they make the drift readable while tuning the feel.

Performance constraint (device-verified: per-segment strokes turned choppy
on an iPhone 13 mini once marks piled up): marks must render as a **few
batched paths** — segments baked into fixed-size chunked `Path`s per visual
bucket, oldest chunk dropped first, recorded at half tick rate with a
minimum segment length. Keep the total budget modest; fewer marks beat a
choppy sim.

### Cars (procedural, open-wheel)

Cars render as classic buggy-style open-wheelers, old-F1 silhouette: a narrow
body with all four tires visible outside it, in the per-player colour. A
handful of procedural shapes, no image assets; the visible tires are what
anchor the skid-mark trails (and can later show steering angle).

### Car contact is a race option, not a constant

Two race modes exist from the moment a second car does, as a per-race flag on
the sim (both run the identical deterministic step):

- **Contact** — cars collide and bump each other; hectic, derby-flavoured.
- **Ghost** — cars pass through each other; the classic pure-speed skill
  race. Render overlapping ghost cars slightly transparent so pileups on the
  racing line stay readable.

Walls and surfaces behave the same in both; only car–car interaction toggles.

### AI drivers (an input source, like everything else)

An AI opponent is a **pure deterministic function** of car state + track
producing the same car-relative `CarInput` a thumb would — reproducible in
tests, replayable, lockstep-safe. It aims at a lookahead point along the
centerline, lifts for upcoming curvature, and backs out when pinned
(stuck-recovery is its only memory). **No rubber-banding, ever**: difficulty
is a skill ladder over the driver's own dials (lookahead, throttle cap,
corner caution) — AI cars are mechanically identical to players', per the
no-upgrades rule. AI fills empty grid slots; it must never be needed to
make solo play work.

### Time trials, ghosts, hiscores (determinism pays twice)

Because the sim is deterministic and inputs are data, a **replay is just the
RNG seed + the per-tick input stream** — tiny to store. That enables:

- **Time challenges** — solo time-trial mode; local hiscores per track (best
  lap, best race). Local only; global leaderboards stay out of scope.
- **Ghosts** — a hiscore replays as a translucent ghost car driven by its
  recorded inputs through a parallel sim run. Ghosts never interact with the
  live race (regardless of the contact flag) and never write marks.

**Record seed + inputs from the first build that can finish a lap** — replay
data cannot be retrofitted onto bests that weren't captured, even though the
time-trial UI and ghost playback land later.

## Control schemes (two, swap freely against the same sim)

The A/B is settled — down to **two** schemes, toggled by the in-run
switcher:

- **Casual** — aim-to-drive: a floating stick whose *angle* is where you
  want to go; the sim flips the car's body toward it (speed-scaled) and the
  drift carries the speed there. No countersteer, no separate gas/brake.
- **Pro** — the direct steer/throttle d-pad (analog, with flip-assist so it
  drifts too); the scheme the keyboard target reuses.

Why only two: on glass, holding a drift by manual countersteer needs a
precision touch can't give — so the accessible drift (Casual) and the
direct-control drift (Pro) are the two that earn their place; slide,
two-zone, one-touch, and split were cut. Settled feel rules: steering works
**while coasting**; the body-flip is speed-gated (a parked car can't spin)
and curved (gentle at low speed); a drift **redirects** momentum rather than
scrubbing it (arcade — never manufactures speed). The **Tuning panel** (pause
menu) exposes every live-tunable dial (Casual: flip rate/speed boost/reverse/
gas ease; Pro: dead zone/travel/steps/curve/turn rate/flip; shared: drift
keep, grip, **Pace**). Physics dials apply on Reset and hiscores only record
on stock physics; the rest apply live.

**Control zones.** "Pad appears where the thumb lands" alone doesn't scale
past one player: each player owns a **zone** (screen region) and the control
materializes wherever the thumb lands *within it*, clamped to fit inside.
Zones carry their own **`up` vector** — schemes compute against it, so a
corner-seated player's zone rotates to face them and control orientation is
never ambiguous. On-screen controls are **tinted the owning car's color**.
A touch belongs to the zone it started in for its whole life. Seating is a
**setup choice, never a guess**: 1P full screen; 2P picks **side-by-side**
(left/right halves) or **face-to-face** (top/bottom, top flipped); 3P picks
which quadrant stays **open**; 4P quadrants. Top-row zones' `up` flips
(sitting across a tabletop device). Shared screens show faint zone outlines
with a color tab on each player's home edge.

**Chrome respects the zones.** On shared screens, each player's HUD chip
sits in their own zone's home corner, rotated to face them; the countdown
mirrors for flipped players. Meta actions (scheme, reset, exit) never float
over someone's thumb area — during a race there is exactly one small
**pause** button on the zone seam (screen center, over the infield), and
everything else lives in the pause menu behind it (pausing freezes the sim
and the clock). System edge swipes are deferred (`defersSystemGestures`) so
a thumb at the screen edge doesn't summon Control Center mid-corner.

One-thumb (one touch per player → 4 players fit even on an iPhone's ~5-touch
limit; iPad ~11):

1. **Virtual d-pad** *(current default)* — d-pad materializes at the thumb
   within the zone; toward `up` = throttle, pull back = brake/reverse,
   sideways = steer, diagonals blend; per-axis output quantized into a few
   steps (currently 3), short travel.
2. **Arcade touch-pad ("slide")** — thumb down = gas, sideways offset from
   touch-start = steer, release = coast. Simplest; A/B verdict so far:
   binary always-on gas feels wrong on glass.
3. **Two-zone tap-steer** — hold anywhere = gas, left half = turn left, right
   half = turn right.
4. **One-touch** — permanent gas, touch = turn. Radically simple; cheap to
   try. Open design flaw from the first trial: turn-one-way-only means a
   right turn needs a full circle — classic one-button racers dodged this
   with tracks that only turn one way, which ours won't be. Candidates
   before the A/B: **tap flips direction, hold turns** (fully general, costs
   a tap-vs-hold timing gate — the favourite); alternating per tap is
   broken (two same-direction corners in a row force a wrong-way turn);
   restricting the scheme to mostly-one-direction tracks demotes it to a
   gimmick. If no variant reads well, cut the scheme.

Two-thumb (richer, fewer players per device):

5. **Split gas/steer** — one thumb throttle+brake, other thumb steer.

Non-touch (Mac-prep / controller path):

6. **Keyboard** (Mac) — arrows/WASD; the keyboard-era classic, viable for 1–2.
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

## Conventions (apply once real code exists)

- **Toolchain:** Xcode + Swift 6, **XcodeGen** (`.xcodeproj` generated,
  gitignored, never committed). The team ID IS committed in `project.yml`
  (it's not a secret, and the release lane's headless automatic signing
  needs it); certs/profiles are fetched by `-allowProvisioningUpdates`.
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

**No performance tuning or upgrades, ever.** Every car in a race is
mechanically identical; progression (career ladder, unlocks) may only ever
grant **cosmetics** to show off. Why: upgrade trees are a long-run balance
burden, and the game is about player skill — a newcomer on their first race
must face the same machine as the veteran. ("No accounts" means no
server/online accounts; local on-device player profiles are fine.)

## First milestone (do this, nothing more)

One car, one static track, the deterministic arcade-drift sim, and a
`ControlSource` protocol with the **arcade touch-pad** implemented — plus at
least one more scheme stubbed so swapping is exercised early. Goal: drive one
car around and answer "is this fun?" No multiplayer, no AI, no menus, no
netcode yet.

Surface-wise the first track needs only asphalt + grass (the seam that proves
the surface model); mud, water, and oil slicks are content to add once the
drift is proven fun. Skid marks are the one piece of polish allowed in early —
they're feedback for tuning, not decoration.
