# Jump pieces

> **Shipped.** Option A (one piece: lip · gap · landing) and elevated jumps, as
> recommended below. What the build actually taught, beyond the plan:
>
> - **A straight samples only its two endpoints**, so the gap had nowhere to live
>   and silently never appeared. Gapped pieces are now densified the way a climb
>   already was (`PlacedPiece.gapSpans`).
> - **The launch line was on the wrong side of the hole.** It was built from
>   `exits[0]` — past the landing — so a car fell in and was thrown only after
>   crossing. Harmless while a "jump" was solid road; fatal once the gap was real.
>   It now sits at the lip.
> - **The gap had to be sized against measured flight**, not chosen: asphalt casts
>   a half-width end cap into the gap from each side, and a launch carries only
>   113 units at top speed. See `Piece.gapSpan` for both numbers.
> - **`isAirborne` does not mean "launched"** — a car falling into the gap is
>   airborne too, so the tests assert on the car's *rise above the lip*. Deleting
>   the launch kick outright left an earlier version of them green.
>
> The remaining item is the drivability warning (§5), deliberately deferred.

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
