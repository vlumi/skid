# Jump pieces

> **Shipped — but not as this plan describes.** Two device rounds rejected the
> single-jump-piece design below, and the final shape is three separate things:
> a **wedge ramp**, a **gap** (1U, absence of road), and a **warp** (zero length,
> drops the road to where it continues). See `docs/track-pieces.md` for the
> as-built description; this file is kept for the reasoning that got there.
>
> What the plan got wrong, in order of how much it cost:
>
> - **A jump should not be a piece.** Composing it from parts that each stand
>   alone removed every special case: a gap works anywhere road is missing, a warp
>   anywhere a step down is wanted, and the flight is a consequence of geometry.
> - **The launch kick was the wrong mechanism.** It had to be tuned to a gap
>   width and fired even on flat road. Deleting it (with `launches`,
>   `launchPerSpeed` and the "Launch" slider) and letting a car drive off a real
>   slope is both simpler and honest — and the eased ramp top, which flattens the
>   last 5% to nearly horizontal, is what had made a ramp lip launch nothing.
> - **There is no upward arc, on purpose.** "Cars are heavy and don't jump up
>   high anyway" — a car drops off the lip, and speed buys distance before
>   landing.
> - **Sizing the piece was moot.** The 2U → 4U analysis below is real (asphalt
>   reaches a half-width past its last solid point; a crossing road must land on
>   the lattice) but a chained 1U gap made the question disappear.
>
> Three implementation traps worth remembering: a straight samples only its two
> endpoints; a zero-length piece stamps duplicate centerline points that pave the
> gap beside it; and `isAirborne` is true for a car *falling in*, so it cannot
> witness a launch.

## What already exists

Almost all of it. This is not a from-scratch feature; it is finishing one.

- **The catalog entry.** `ID.jump = 40`, `kind: .jump`, a 2U straight with
  `launches: true` (`PieceCatalog.swift:166`).
- **The launch line.** The compiler emits a `Ramp` across the road at the
  piece's exit for any `launches` piece (`PieceCompiler.swift:270`).
- **Ballistic flight.** `applyRamps` kicks `verticalSpeed` by
  `velocity.length * launchPerSpeed`, then gravity brings the car down and
  flight ends when it meets a surface. Speed-scaled, so distance is quadratic
  in speed — clearing a gap is earned.
- **The overlap carve-out.** `TrackValidator.legallyCrossing` already permits a
  road to pass under a jump.

## What is missing: the gap

**A jump today is a launch lip over solid road.** Nothing removes the
centerline under the piece, so the car flies and lands on the road it never
left. The flight is real; the risk is not.

That is the whole feature, and it is the one open design question the plan has
to settle, because it decides the piece model.

### The question

Does a jump piece own its gap, or is the gap a separate piece?

**Option A — the jump piece is lip + gap + landing, one 2U span.** What the
catalog entry and `docs/track-pieces.md` already describe. One tap places a
complete, always-valid jump. The gap length is fixed by the piece, so the
required speed is fixed too.

**Option B — a lip piece, N gap pieces, a landing piece.** The author sets the
gap width, so a jump can be easy or brutal. But a gap is placeable on its own,
which means a track can be built that is impossible to complete, and the
closure search and the drivability warning both have to reason about it.

**Recommendation: A now, B never as a replacement.** A is one tap, cannot be
built wrong, and needs no new validation rules — and the fixed gap is a
*feature*, because it makes "can I clear it?" a question about the car and the
driver rather than about the author's arithmetic. If a variable gap is wanted
later it can be a second, longer jump piece (`jumpLong`), which is a new
catalog id and nothing else: no new failure mode, no new validation.

This is the same reasoning that put compounds behind the primitive palette —
offer the shape that cannot be assembled wrong.

## The build

### 1. The gap in the compiled road

The centerline must stay a **single closed loop** — the whole runtime depends on
it (progress, lap scoring, `distanceToCenterline`, the AI). So the gap is not a
hole in the centerline. It is a span marked as **not asphalt**.

The honest model, and the one that matches how height already works: the
compiler records the jump's span, and `isOnRoad`/`onOwnRoad` return false
inside it. The centerline still runs through — progress and the AI are
unaffected — but there is no surface to stand on, so a car that fails to clear
drops to whatever is beneath (grass, or a road laid under the gap).

Concretely: a `gaps: [ClosedRange<Double>]` on `Track`, in centerline
arc-length, consulted by the same surface lookup that `applyRamps` already uses
for "is there road under me at my height". One place, because there is already
exactly one place that answers that question.

**Do not** implement this by deleting centerline points. That breaks loop
closure, and progress would jump the gap's length.

### 2. Flight over the gap must not clip

`collideWithWalls` runs while airborne and compares `car.height` to wall
height. A car flying across the gap at height ~0.1 will hit **ground rails**,
including the jump piece's own. The jump piece must therefore emit no side
rails across its span — which is what the `railed` attribute (#132) already
expresses, so this is a compiler condition, not new machinery.

### 3. Reachability: the hotbar

`EditorView.hotbarPieces` returns `[]` today, with a comment saying jumps join
it when they land (`EditorPalette.swift:74-83`). That comment becomes true:
`hotbarPieces = [ID.jump]`, a `pieceLabels` entry ("Jump"), and a `PieceIcon`
that draws a lip and a gap. `HotbarSlot.defaults` gets the jump, since an empty
default hotbar is the reason nobody would find it.

### 4. Jumps above ground

The user asked: can a jump sit above level 0, and how far does the car fly?

It can, and it needs no special case — the launch kick is vertical and relative
to the car's current height, and landing is "whatever surface is beneath". A
jump at height 2 over a gap with a road at 0 under it is already expressible and
already meaningful: clear it and you continue at 2, miss and you fall two
storeys onto the road below. That is the most interesting thing in this feature
and it costs nothing extra.

Apex is small by design — ~0.12 levels at the measured tuning
(`docs/height-groundwork-plan.md`), so a jump reads as a *gap crossed*, not a
launch into orbit. The scale-up-when-airborne render cue is what sells it.

### 5. The drivability warning

`Track.blockages()` samples the centerline for walls that stop a car. A gap is
not a blockage — it is passable at speed — so it must not be reported as one.
But "this gap needs ~X speed and the run-up gives you Y" is exactly the kind of
thing the warning exists to say. Worth doing *after* the gap lands and the real
numbers are measurable on device, not guessed here.

## Two incidental findings

Both are pre-existing and small; fold them in where they touch this work.

- **`launchLine` uses a flat `width / 2`.** Same bug as the eight-plus sites
  fixed in #133/#139: at height *h* the drawn and gripped road is
  `Elevation.scale(atHeight:)` wider, so an elevated jump's launch line is short
  by ~12 units per storey at each end — a car near the road edge would miss the
  lip and not launch at all. *(Fixed. The same function turned out to have the
  worse bug above: it was positioned past the landing.)*
- **`CarTuning.jumpTicksPerSpeed` is dead** — declared and initialized, read
  nowhere. It is the pre-ballistic flight timer, obsoleted when flight became
  "until you meet a surface". Delete it.

## Verification

`make test`, `make lint`, `make build-ios`, checking **exit codes**.

Tests, each with the sabotage that must turn it red:

- A car crossing the jump at high speed lands **past** the gap and continues —
  sabotage: remove the launch kick, it must fall in.
- A car crossing slowly **falls into** the gap. This is the test that proves the
  gap exists at all; against today's code it fails, which is the point.
- `isOnRoad` is false at the gap's midpoint and true just outside it — sabotage:
  drop the gap span, both become true.
- Centerline **loop closure and total length are unchanged** by a jump, and lap
  progress across a jump advances by the piece's length, not more — this is what
  catches a "delete the points" implementation.
- A jump at height 2 over a road at 0: undershoot lands the car at height 0, not
  2 — sabotage: hardcode landing to the launch height.
- No rail wall is emitted across the jump's span, and a car flying the gap is
  not stopped — sabotage: emit the rails, the flight clips.
- The launch line spans the **scaled** width at height 2: a car at the road edge
  still triggers the launch. Sabotage: restore the flat `width / 2`.

Then on device: it is a jump, and whether it *feels* like one is not something
this document can settle.
