# Flexible tracks: fix plan

Ordered steps toward tracks that are pleasant to *build*, ending with a fitting
piece that closes a loop the quantized catalog cannot. Steps 1–3 stand on their
own and are worth doing whether or not step 4 pans out — that is the point of
the ordering. Ground rules per step: write the failing test first and **measure
before asserting**; `swift build`/`swift test` from the repo root are the
authority; `make format && make lint` before committing; no changelog bullets
for faults introduced and fixed inside one unreleased build.

Backwards compatibility is **not** kept (maintainer's call). Old codes must
convert once, not decode forever — see step 3.

## Why: the mixed-diagonal problem

Straight runs come in two families. An axis-aligned straight displaces by whole
units; a diagonal one displaces by `n·√2/2` per axis. Only 45° arcs mix the two.
So closing a loop that uses both means driving *two* independent quantities to
zero at once — the integer part and the √2 part — with straight lengths as the
only knobs. That is why a mixed figure-eight feels like solving simultaneous
equations instead of designing a track.

Measured on a concrete mixed eight (axis lobe + diagonal lobe, four 90° corners
each, 45° transitions between families): the heading returns correctly to 0, and
the residual gap is `dx = 2·(√2/2)`, `dy = 2 − √2 ≈ 0.586U`. No corner can absorb
that. A single straight cannot either — it has one degree of freedom and the gap
has two components (the lateral one is the problem).

## 1. The start line becomes an ordinary piece

**Today** three roles pile onto one piece: where the walk begins, where the ring
closes, and where the start line is. `PieceCompiler` builds the grid from
`walk.placed[0]`; `TrackValidator` requires seam 0 gated and treats seam 0 as the
ring's join; several places id-check `PieceCatalog.startPieceID`.

**Change.** The start line is a piece like any other, placed anywhere, and
deletable. The invariant becomes a save-time rule: **exactly one start line
somewhere on the ring**. Reversing a track is then just placing the start line
facing the other way.

- `startGrid(at:)` takes the piece that *is* the start line, found by id, not
  position 0.
- The validator's rule changes from "seam 0 is the start" to "exactly one start
  piece exists"; the finish gate is the start piece's exit seam, wherever that is.
- Compiler emits gates with the start piece's seam last (the runtime convention
  that the final gate is start/finish is unchanged).

**Test.** A track with the start line at piece 5 compiles, laps, and reports the
same lap count as the same track with it at piece 0; a track with zero or two
start lines fails validation with a specific problem.

## 2. Canonical normalisation for encoding

With the start line free to move and (step 4) a fitter to anchor at, the same
track could be written several ways. Codes are identities, so **one track must
have one encoding**.

**Rule.** Rotate the piece list at save time: begin at the fitter if one exists,
otherwise at the start line, and walk forward from there. Decode is unchanged —
it still just walks the list in order — so this costs nothing at runtime and
keeps decoding dumb.

**Test.** Building the same ring from different starting points, in either
direction, yields byte-identical codes.

## 3. Convert the stored tracks once

No compatibility shim. A format version byte is added so an old code fails
**loudly** rather than decoding into nonsense — worth having even with no
compatibility promise, because a silently misread code is a miserable bug.

- A one-shot converter re-encodes the built-ins and the maintainer's saved codes
  into the new format (start line as a piece, normalised order).
- `TrackLibrary`'s built-in codes are replaced with the converted ones.
- Acceptance: every converted track compiles to geometry identical to what it
  compiled to before (same centerline, same gates, same lap count), and the AI
  still laps each of them.

## 4. The fitting piece — curve + straight + curve

A piece whose job is to close the ring when the catalog cannot. **Shape: two
arcs of equal, opposite turn with a straight between them** — a smooth lateral
jog that enters and leaves on the same heading. Not a sharp offset at either end
(maintainer's call), and no new corner vocabulary: radius comes from the existing
three, and the arcs' angle is free rather than restricted to 45° multiples.

**Parameters:** radius (catalog: 1/2/4U), arc angle (continuous, **and zero is
allowed**), middle length (continuous). Two continuous unknowns, which is exactly
what a two-component gap needs.

**Zero degrees is not an edge case to tolerate — it is what makes the piece
total.** At θ = 0 both arcs vanish and the shape *is* a straight of length L
(displacement `(L, 0)`, and the radius becomes irrelevant). So the fitter
subsumes the plain custom-length straight, and every pure-longitudinal gap is
reachable by construction rather than needing a different piece.

**Verified reachable** (numerically, radius 1–4U, arc 0…90°, middle ≤ 8U):
- the measured mixed-eight gap `(2.0, −0.828)U` → **R=1U, 29.28° arcs, 1.172U
  middle**;
- `(3.0, 0.5)U` → R=1U, 10.04°, 2.692U; `(5.0, 2.0)U` → R=2U, 26.17°, 3.606U;
- **the whole `dy = 0` line**, via θ = 0: `(2.0, 0)U` → 0°, L = 2U; `(0.5, 0)U`
  → 0°, L = 0.5U. (An earlier version of this plan recorded `dy = 0` as
  unreachable. That was the solver requiring θ > 0, not the geometry.)
- **not** reachable: a gap that is both short and laterally offset — too little
  room for two arcs plus a straight (`dx` below roughly 1.5–2U while `dy ≠ 0`,
  depending on radius).

So validity still has a **lower** bound, but only for offset gaps. When the ends
are inside that dead zone the honest editor hint is "these ends are too close to
bridge — lengthen one side" rather than "cannot close", and the nearest reachable
pose is computable, so the hint can name a direction.

**Rules that make it tractable:**
- **At most one per track**, and it may only be inserted to *join the loop* —
  never in open chain. A closed ring has exactly one place where two ends of a
  linear build meet.
- **While a fitter exists, no other piece may be removed from the ring** — its
  geometry is derived from both neighbours, so deleting elsewhere invalidates it.
  The editor must say so when the user tries.
- **Drawn like any other piece**, with a discreet marker that it is the fitter —
  needed precisely so that "why can't I delete this?" has a visible answer.
- **Its geometry is derived, not stored.** With the walk normalised to start at
  the fitter (step 2), both chains grow outward from it, so both loose ends are
  known before the fitter is evaluated. It needs an id in the stream and no
  payload, which also sidesteps the forward-reference problem: a piece meaning
  "whatever reaches the next piece" is unencodable when the next piece's pose
  does not exist yet.
- **Solvability is validity.** A track whose fitter has no solution does not
  save. The check belongs in `TrackValidator` next to the overlap rules.

**Test.** The measured mixed-eight closes and compiles; a fitter in the dead zone
fails validation with the actionable problem; deleting a ring piece while a
fitter exists is refused; the reachability boundary is pinned by the numbers
above; a fitter track round-trips byte-identically through encode/decode.

## Rejected along the way

- **A single custom-length straight** as a *separate* piece. One degree of
  freedom against a two-component gap: it closes only when the gap lies along its
  own heading, which the mixed eight's does not. Not rejected as a *shape*,
  though — it is the fitter at θ = 0, so it comes for free rather than needing
  its own id.
- **Two custom straights, one per lobe** (axis `2.0U`, diagonal `−0.83U` for the
  measured case). Honest to the geometry and needs no new piece — but one length
  comes out negative, meaning "shorten that lobe", and it drops the single-fitter
  invariant in favour of two special pieces per track.
- **`arc + L1 + arc + L2` with quantized 45° arcs.** Reaches an area, but forces
  corners the author did not ask for and has a wider dead zone than the smooth
  jog.
- **Forks and joins.** Parked separately: the tracks are too small to afford
  branching, and the cost is route choice rather than geometry. See ROADMAP.
