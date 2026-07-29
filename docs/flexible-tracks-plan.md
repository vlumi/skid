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

**These steps are MODEL work only.** Each one makes the model able to express
something; the editor UI that lets a user *do* it comes with the editor overhaul
(the selection model and its dependents), which has to happen before these
pieces fall together anyway. So "the start line can sit anywhere" means the
compiler, validator and renderer handle it — not that there is a button for it
yet.

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

**Done** (model half). Smaller than this plan predicted: the "exactly one start
piece" rule already existed, and the editor renderer already found the piece by
id. Three real welds: the compiler's grid came from `walk.placed[0]`; the finish
gate was hardcoded to seam 0; the validator required seam 0 to be gated. All
three now key off the start piece's index. One bug fell out — the editor skipped
drawing a chevron at seam 0 on the assumption it was the start line, so on a
rotated ring it drew one ACROSS the start line and left the real seam 0 bare.
Deleting and inserting the start line is editor work, and waits for the overhaul.

## 2. Canonical normalization for encoding

With the start line free to move and (step 4) a fitter to anchor at, the same
track could be written several ways. Codes are identities, so **one track must
have one encoding**.

**Rule.** Rotate the piece list at save time: begin at the fitter if one exists,
otherwise at the start line, and walk forward from there. Decode is unchanged —
it still just walks the list in order — so this costs nothing at runtime and
keeps decoding dumb.

**Test.** Building the same ring from different starting points yields
byte-identical codes.

Note **reversal is not normalized away**: the same loop driven the other way is a
different track (every corner swaps hand), so it keeps its own code. Only
rotation is a re-spelling.

**Done.** `TrackLayout.normalized()` rotates a closed ring to begin at the start
line, carrying `origin`/`originHeight` to the new first piece (they describe
piece 0, so rotating without them moves the track) and shifting `gateSeams` and
`pitches` by the same offset. `TrackCode.encode` calls it. Open chains are
returned untouched — mid-build, the first piece is where the author started and
the two ends are not interchangeable.

All four shipped built-ins were already canonical (start line at index 0), so no
code changed; a test pins that, and fails loudly if a future built-in is authored
otherwise.

One correction from the investigation: an earlier reading of mine claimed gate
seams "drift" when compound pieces expand on decode, measured as gates landing
443 units apart. That was an ill-posed comparison — a hand-written compound
layout against its own expansion, which are two different layouts, since **seams
index the decoded primitives**. The real round trip is exactly stable: 19
primitives in, 19 out, identical seams, gates 0.0000 apart.

## 3. Convert the stored tracks once — NOT NEEDED

Planned as a one-shot conversion behind a new version byte. It turned out there
is nothing to convert, so nothing was written. Three reasons, each checked rather
than assumed:

- **Steps 1 and 2 did not change the format.** Step 1 moved where the compiler
  and validator *look* for the start line; step 2 rotates a ring before writing
  it. Neither alters what the bytes mean.
- **Every existing track already anchors at its start line**, so it is already in
  canonical form. Verified for all four built-ins (start line at index 0,
  re-encoding reproduces the stored code byte-for-byte, same gate count and road
  length as before), and the maintainer confirmed the same for their saved codes.
- **The version byte and the loud failure already exist.** `TrackCode` carries
  `version = 1`, and `decode` throws `badVersion` on a mismatch — verified.

So no bump: bumping would invalidate every existing code to no purpose. The
version byte is there for when the format genuinely changes — the fitting piece
(step 4) may be that moment, since it adds an id and possibly a payload.

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

**Scope for the first cut** (maintainer's call): the fitter may be inserted
**only as the last piece, closing onto the start line**. The editor builds
one-way, so that is the only position it can currently be placed at anyway, and
it is exactly the position the closure suggester already reasons about. That makes
step 4 a palette entry plus a solve, not an editor overhaul — and it is enough to
test and verify the geometry on a real device, which is the point of doing it now.

**What already fits it.** `ClosureGap` (TrackLayout.swift) splits the gap into the
axis part and the *diagonal* (√2) part — the two currencies the fitter has to
settle — plus `headingEighths`. So the solve's inputs exist; the fitter is a
one-piece answer where `ClosureSearch` returns a multi-piece run.

**Rules that make it tractable:**
- **First cut: one per track, inserted last, closing onto the start line.** Not
  because the model requires it — see the storage note below, which removes that
  constraint — but because that is what a one-way editor can place and what is
  needed to verify the geometry on a device.
- **No special deletion rule.** Because the fitter stores its own solved shape it
  does not depend on its neighbours, so removing another piece cannot invalidate
  it: the loop simply stops being closed, which is ordinary mid-build state the
  editor already handles. (An earlier draft of this plan forbade deleting any ring
  piece while a fitter existed, and made "at most one" a hard rule. Storing the
  solve retires both.)
- **Drawn like any other piece**, with a discreet marker that it is the fitter —
  needed precisely so that "why can't I delete this?" has a visible answer.
- **Geometry is SOLVED ONCE AND STORED** — radius, arc angle, middle length —
  not re-derived on decode. Roughly 4–5 bytes: 2 bits of radius (three catalog
  values), the angle in fixed point, the length in fixed point. The reserved
  112–127 block is for byte modes, so this wants a plain id plus a payload
  section.

  **The reason is determinism, not precision.** The closure residual is ~1e-12
  units against a device pixel of ~0.97 units on a phone — twelve orders below
  visible, ten below the tightest gameplay tolerance (`surfaceTolerance` 0.12).
  That part is harmless. But AGENTS.md commits Phase 2 networking to
  **deterministic lockstep** — same inputs, same state, bit-for-bit — and `sin`
  and `atan2` are not required to be correctly rounded, so two devices each
  re-solving the same fitter can differ by an ULP. Lockstep has no tolerance for
  that: a 1e-12 difference in geometry compounds through collisions.

  Storing the answer means every device walks identical numbers, decode does no
  trig, and the forward-reference problem never arises — a stored fitter works
  anywhere in the stream, which is what makes multiple fitters and free deletion
  possible later.

  **Consequence worth naming: a track of nothing but fitters is a freehand
  track.** Once each one carries its own shape, the quantized catalog is the
  convenient path rather than the only one, and an author could build a whole loop
  out of curve-straight-curve pieces at arbitrary angles. The budget allows it —
  the piece limit is 127 and ~5 bytes each keeps even 30–60 of them inside a
  comfortable code. Not a goal, and not something to design *for* yet, but it
  should be allowed to work rather than accidentally forbidden, and it is a
  plausible future "freehand mode" for whoever wants one. What it must not break:
  the overlap validator and the closure rules apply to fitters exactly as to
  anything else.
- **Solvability is validity.** A track whose fitter has no solution does not
  save. The check belongs in `TrackValidator` next to the overlap rules.

**Test.** The measured mixed-eight closes and compiles; a fitter in the dead zone
fails validation with the actionable problem; the reachability boundary is pinned
by the numbers above; a fitter track round-trips byte-identically through
encode/decode; and a decoded fitter reproduces the authoring device's geometry
exactly, since that is the determinism claim.

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
