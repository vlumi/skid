# Height model: fix plan

Ordered steps for the known soft spots in the ramp/bridge/height model, sized
so each is one verifiable change. Do them in order — 1 and 2 are prerequisites
for tunnels (4) and curved ramps (5). Ground rules for every step: write the
failing test first and **measure before asserting** (probe the actual heights/
distances, then encode them); run from the repo root with `swift build`/`swift
test` as the authority; `make format && make lint` before committing; no
changelog bullets for faults introduced and fixed within the same unreleased
build.

## 1. Sample-level heights in overlap checking  — the one real bug

**Fault.** `TrackValidator.hasIllegalOverlap` exempts piece pairs by
`abs(entryHeight_i − entryHeight_j) > 0.5` (TrackValidator.swift:148). A ramp
spans 0→1, so judging it by its entry height is wrong at one end: ground road
crossing a `rampDown`'s LOW half (both physically at ground level) is exempted
as "different layers" and validates, yet the ramp's low side rails block ground
cars there — a track that validates but is partly undrivable. The closure
search repeats the pattern (ClosureSearch.swift ~261).

**Fix.** Heights move into `RoadProximity`'s segments:

- `RoadSegment` gains `height: Double`. Build segments from
  `heightedSamples(degreesPerSample: 20)` instead of `centerlineSamples`,
  lerping height when the densification subdivides a span.
- The layer exemption moves INSIDE `RoadProximity` (`abs(hA − hB) > 0.5` per
  segment pair). The validator's `exempt` closure shrinks to `legallyCrossing`
  only; `ClosureSearch` drops its `heights` array and height closure.
- Search candidates: cached origin shapes can't carry absolute heights. Pass
  the candidate's entry height and `heightDelta` into `conflicts(...)` and
  compute per-segment height by arc fraction (`inPiece / pieceArc`).

**Tests.** (a) A layout routing ground road across a descending ramp's foot
must flag `.overlap` — build the fixture with the editor-style API and probe
the crossing samples' actual heights BEFORE writing the assertion. (b) The
eight (ground road under mid-deck) must stay exempt. (c) All built-ins still
validate (existing tests cover this — they must stay green untouched).

## 2. Derive the under-deck cap; pin the cap↔climb coupling — DONE

Done differently (and better) than planned below: the cap is now a **gate**
wall kind — "blocks every car below my height, passes everyone at or above" —
at `level − reachTolerance`, so the bespoke 0.9 constant is gone entirely and
the seal says what it means: you may not enter from a road below this level.
`RampGateTests` pins the remaining physics coupling both ways (analytic
inequality over every catalog ramp + a flat-out drive-over per ramp pairing).
A tunnel mouth will want the mirrored kind (blocking from above) in step 4.
Original notes:

**Fault.** `underDeckCapHeight = 0.9` (PieceCompilerWalls.swift) works only
because a flat-out climber on a 240-unit ramp arrives at ~0.99, an artifact of
`Race.maxHeightChangePerTick = 0.08` and the ramp's length. Lowering the climb
rate — or adding a shorter/steeper ramp — silently makes legitimate climbers
hit their own exit cap.

**Fix.** Make the relationship explicit rather than clever:

- Add an analytic assertion test: for EVERY ramp piece in the catalog, the
  minimum arrival height of a top-speed climber
  (`rampArcLength / (maxSpeed · dt) · maxHeightChangePerTick`, capped at 1)
  must exceed `underDeckCapHeight` with margin. This is the tripwire that
  fires when someone adds a too-steep ramp or retunes the climb.
- Add a behavioural test that actually drives a car at full throttle up each
  ramp onto the deck and asserts no `wallImpact` (an AI-driver-style input, not
  a coasting car — a coasting car never gets there; this trap has been hit
  before).
- Keep 0.9 as the value if the asserts hold; the point is the pinning, not a
  new number.

## 3. Level-aware helpers to replace the two-level idioms — DONE

`Track.level(of:)`, `isOffGround(_:)`, `withinLevels(_:)`, `lowestLevel` /
`highestLevel`, `levelSeparation` (TrackLevel.swift); eleven sites converted
across SkidCore and SkidKit, zero behaviour change (suite untouched). Tunnels
start by lowering `lowestLevel`. `Race.blocks`' rail trunc stays, commented as
embankment-only per step 4. Original notes:

**Fault.** "There are exactly two levels" is baked in as scattered idioms:
`trunc(wall.height)` as which-level-owns-this-wall (RaceWalls.swift:66),
`entryHeight > 0.5` for who gets rails (PieceCompiler.swift:226),
`exitHeight > 0.5` for when the search offers ramps (ClosureSearch.swift:61),
`height >= -0.001, height <= 1.001` bounds in `extend`, and the `> 0.5` layer
comparisons. A tunnel level (−1) would be misclassified by every one of them —
e.g. tunnel pieces would get NO rails at all, and the search could never
suggest climbing out of a tunnel.

**Fix.** Purely mechanical, **zero behaviour change** (tests must pass
untouched — do not "improve" anything in this step):

- Add named helpers on `Track` (or a small `HeightLevel` enum): `level(of:)`,
  `sameLevel(_:_:)` (today `|Δ| ≤ 0.5`), `groundLevel`/`deckLevel` constants,
  and named search bounds (`minLevel`/`maxLevel`).
- Replace each idiom call-site with the helper, one commit, so tunnel work
  later changes ONE definition instead of hunting five files.
- Leave `trunc(wall.height)` in `Race.blocks` as-is but comment it as
  embankment-only, pending step 4's design.

## 4. Tunnels: design before code — SPEC WRITTEN, awaiting sign-off

The spec lives in docs/track-pieces.md ("Planned: tunnels (level −1)"):
the decided cutting rule plus proposals for falling, one-way walls, cutting
solidity ([h, 0] — the same interval rule mirrored), lowestLevel = −1, and
the porthole prerequisite. Code starts only after the proposals are approved.
Original notes:

The embankment model does not mirror to tunnels — a tunnel ramp is a
**cutting**, and the danger inverts: nothing drives "under" it; instead
ground-level cars must not enter it from above/beside. Also
`underDeckCapHeight` is an absolute deck-relative number: applied naively to a
0→−1 ramp, the cap lands at 0.9 ABOVE ground and walls off the ground road at
the tunnel mouth.

**Decided (maintainer, 2026-07-27) — the cutting model:**

- A tunnel ramp is **a hole in the ground you can always fall into**: entering
  the cutting is allowed from ANY direction — over either end or across its
  sides. A car that comes in from the side falls to the ramp surface below.
- **Leaving is what's restricted**: out the low end into the tunnel, out the
  high end onto the ground. The sides are walls **from the inside only** —
  one-way walls, passable inward, solid outward.
- The mouth seals mirror the embankment gate: a `gate` blocks entering from
  the storey below; the tunnel needs the mirrored kind blocking entry from the
  storey ABOVE (its own case in `Wall.Kind`, not a flag). The gate is already
  bounded to exactly one storey, so deck gates ignore tunnel traffic below by
  construction.

**Still to settle in docs/track-pieces.md before code:**

- How "falling in" plays: the height chase downward (instant, or faster than
  the climb clamp — a fall isn't a climb), and what happens to speed on
  landing.
- One-way walls in `Race.blocks`: the side rail of a cutting needs a
  directional test (which side of the wall the car approaches from), which no
  current kind has.
- Validator: a cutting's footprint is enterable, so RoadProximity's solidity
  interval for tunnel-ramp segments is NOT "solid to the ground" like an
  embankment — decide what it is (probably thin at its own height, since the
  hole is passable space).
- Renderer: draw order below ground, car visibility in the cutting/tunnel
  (per the reveal-beneath/porthole notes), and whether grass exists at −1 /
  what `surface(at:height:)` returns there.

Only after that: extend `HeightLevel` (step 3 makes this one definition),
`extend`'s bounds, the rails condition ("not entirely at ground level"), and
the search's ramp-offering rule (offer up-ramps when below ground, down-ramps
when above).

## 5. The half-height lattice round — REPLANNED (supersedes curved ramps)

Direction decided 2026-07-27, spec in docs/track-pieces.md ("Planned: pitch
and the half-height lattice"): pitched ±0.5 pieces on the ordinary road units
(1U straight, 45° corners at all radii), palette pitch selector instead of
ramp buttons, heights bounded 0…1 this round. Implementation order:

1. `withinLevels` as a validator rule — DONE (`heightOutOfBounds` problem,
   a placement blocker in `canAppend`).
2. DONE (pitch only; walls/kerbs follow the same shape later) — `Pitch` is
   a per-piece attribute on `TrackLayout`/`PlacedPiece` (`climb` = piece delta
   + pitch); `rampUp`/`rampDown` are compounds of two pitched halves with the
   apex seam; expansion/packing are attribute-aware, with a tripwire
   precondition until the mode-switch bytes land (2b); the eight re-encoded
   with migrated seams. Gate thresholds come from each mouth's own height, so
   half-mouths seal at 0.3 and full at 0.8.
3. DONE without code: full-storey clearance already falls out of the
   solidity intervals — road at 0.5 is solid [0, 0.5], so its gap to ground
   is zero and to a deck exactly half a level, both inside the separation
   threshold; the lattice sits on the safe side of every comparison. Pinned
   by tests (half-level road may cross nothing; interval arithmetic at the
   lattice points).
4. Gates/rails per half-mouth (should be automatic); extend RampGateTests'
   drive fixtures to bending climbs.
5. Palette: pitch selector; the ramp sentinel retires.
6. Renderer: wedges/scale are already continuous in height; verify half-level
   resting roads draw sanely.

The original curved-ramp notes below are kept only for the physics numbers:

Prerequisites: steps 1–2 merged. The structure already generalizes
(`capsHighEnd` is property-based, rails follow samples, caps span rail
endpoints), so this is mostly catalog work — with two traps:

- **Radius choice is a physics constraint.** A tight 90° arc is ~188 units of
  road for a 1.0 climb — steeper than the 240-unit straight ramp. Add the
  medium-radius variant FIRST (~377 units, comfortable margin); add tight only
  if step 2's analytic margin proves out. The step-2 tests must automatically
  cover every new ramp (iterate the catalog, don't hardcode piece lists).
- **Never renumber existing ids.** Share codes are byte-stable identities;
  new pieces get NEW ids appended to the catalog. Assert the existing built-in
  codes still decode to identical layouts.

Mechanics: `heightDelta: ±1`, `kind: .road`, `launches: false`, NO expansion
table entry (a curved ramp is primitive — half of it would be a 0.5-height
state, the same argument that keeps the straight ramp whole). Verify the
sloped-piece densification applies to arc segments, not just straights. Wall
tests: one cap per curved ramp, drive-up at full throttle clears it, ground
road passing the ramp's low half is refused by step 1's rule. Palette: the
context-aware ramp button (up from ground, down from deck) needs a decision on
how it offers straight vs curved — hotbar slots are the likely home.
