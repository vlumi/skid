# Editor overhaul: plan

Ordered steps for making the editor edit — both ends, the middle, closed rings
— instead of only appending to one growing end. Ground rules per step: model
before UI, failing test first, **measure before asserting**; `swift build` /
`swift test` from the repo root are the authority; `make format && make lint`
before committing; no changelog bullets for faults introduced and fixed inside
one unreleased build.

**Sequencing: crossings land first** (their own plan:
[crossing-plan.md](crossing-plan.md)). They are engine work with almost no
editor surface, and every edit below re-judges overlap legality — so mid-track
deletion gets exercised against working crossings rather than having them
retrofitted underneath it.

## Decisions (maintainer's, from the design review)

- **Selection is a piece.** Arrows at its free ends disambiguate which end to
  build from; the last-used end is remembered so the common case stays one
  tap. The start piece is the case that forces this: it is the one piece with
  two free ends, exactly when (a one-piece track) the author must pick a
  direction.
- **Build from either end; open chains delete at either end only.** Mid-chain
  deletion of an open chain would slide the whole tail (the walk re-anchors
  everything after the cut) — that is never what the author means, so it is
  not offered.
- **Closed rings delete anywhere.** Canonical rotation makes this nearly free:
  rotate the ring so the victim is last, pop it. Rotation is a re-spelling, so
  the surviving geometry **stays put by construction** — no re-walk, no swing.
  This is the re-anchoring idea, delivered by the flexible-track groundwork
  (start line as an ordinary piece, canonical rotation) that already shipped.
- **No geometry switching in place**, and **pitch-in-place is explicitly
  disallowed** — no use for it (a pitch change breaks height closure for
  everything downstream anyway; delete and rebuild is honest).
- **Variants are applied in place, by long-press.** Decals go onto *laid*
  pieces (a 1:1 id swap — same geometry, different paint), not into the
  palette as pre-decaled pieces that would multiply it. The **start line's
  facing** is the first such variant: long-press the start piece, pick the
  direction. That is also the *only* reversal mechanism — there is no
  whole-track reverse operation.
- **Gating becomes an edit mode**, with gates substantially highlighted while
  it is active. This resolves the seam-tap vs piece-tap conflict outright:
  seam taps toggle checkpoints only in gate mode; piece taps select only in
  build mode.
- **Deleting a gated piece drops its checkpoint silently.** Save-time
  validation already catches an under-gated track; a warning per delete would
  just be noise.
- **Undo, with a long history.** The operations are tiny — a whole layout
  encodes to under ~100 bytes — so keeping hundreds of snapshots costs
  nothing. Not "longer term" any more: delete-anywhere makes destructive
  mistakes easy, and undo is what makes that acceptable.
- **Chrome relocations**: the closure control moves (and carries the fitter
  fallback as its only alternative — a catalog run when one exists, the fitter
  when none does); the "track complete" chip leaves the button column; the
  delete icon stops looking like undo.

## 1. Plumbing: one mutation API

`TrackLayout` today is edited by direct `pieces` manipulation, and three
things are keyed to piece indices: `gateSeams`, `fitters`, and the parallel
`pitches`. Every insert, removal or rotation must remap all three together, or
each editing operation grows its own off-by-one.

One internal API — insert(at:), remove(at:), rotate(to:) — through which every
edit flows, remapping the keyed data in one place. `normalized()` becomes a
caller of rotate rather than its own implementation.

**Test.** Property-style: any sequence of mutations keeps `pitches` no longer
than `pieces`, keeps every `gateSeams`/`fitters` index in range and pointing
at the same *piece* it pointed at before (tracked by identity through the
operation), and `normalized()` results are unchanged from today, byte for
byte.

## 2. Model operations: prepend, end-delete, ring-delete

- **Prepend**: insert at index 0 and move the origin backwards by the new
  piece — pieces invert exactly in the coordinate ring (a straight backwards
  is a straight; an arc backwards is the mirrored arc), so the existing
  geometry does not move.
- **Delete at either end** of an open chain (append-end delete exists; the
  origin-end delete is prepend's inverse).
- **Delete anywhere on a closed ring**: rotate the victim to the end, pop it.
  The ring opens at the cut with two loose ends; the validator re-judges
  everything from scratch — including crossing legality and fitter staleness,
  which is why crossings land first.

**Test.** For each operation: the surviving pieces' world poses are unchanged
(sampled and compared exactly); keyed data still points at the same pieces; a
delete that removes a fitter or a gated piece leaves a valid-but-unsaveable
layout, not a corrupt one.

## 3. Undo

An editor-level stack of encoded snapshots (the code, not the struct — it is
canonical and tiny), pushed per operation, with a long history and redo.
Restore = decode. Undo depth is a constant chosen generously; memory is not a
concern at these sizes.

**Test.** A random walk of operations, undone all the way back, restores the
starting code byte-for-byte; redo replays to the end state.

## 4. Selection UI

Selection is a piece: tap to select, tap empty space to clear, the piece just
placed is selected by default. Delete is anchored to the selection (on it, not
at a fixed screen spot) and hidden when nothing is selected. A selected
piece's free ends draw arrows; tapping an arrow chooses the build end, and the
last-used end is remembered. With the arrows carrying "build here", try
dropping the hazard-striped construction marker — it may be redundant (open
question, decide on device).

## 5. Gate mode

A mode toggle; while active, gates render substantially highlighted and seam
taps toggle checkpoints. Outside it, seam taps do nothing and piece taps
select. The existing gate tap logic (bar hit-testing, near-tie rules) moves
behind the mode unchanged.

## 6. In-place variants: long-press

Long-press a laid piece opens a variant picker. First occupant: the **start
line's facing** (two directions). Decals join when they land, as 1:1 id swaps.

The start-facing variant has a model consequence the UI must not hide: the
compiled track must come out in the *driving direction the start line faces* —
a reversed facing means the compiler emits the lowered centerline reversed,
gates in reversed seam order with flipped forwards, and the grid on the other
side of the line. The AI, arc position and standings all follow the centerline
direction, so they come along for free once the compiler emits it.

**Test.** The AI laps a reversed-facing track; a reversed-facing code differs
from the forward code (already pinned by the normalization tests); grid slots
sit behind the line relative to travel in both facings.

## 7. Chrome relocations

The closure control's new home (carrying the fitter fallback), the "track
complete" chip out of the button column, and a delete glyph that reads as
delete. Decided on device with real screens, last, once the behavior above is
in place.

## Open questions, parked

- **Stale fitters on edit**: auto-re-solve when the gap is still fittable, or
  keep the "close the loop again to refit" hint? Auto is smoother but silently
  reshapes road the author drew. Decide when step 2 makes it reachable.
- **The construction marker** (step 4): possibly redundant next to the arrows.
- **Where the closure control lands** (step 7): with the map actions, or near
  the palette.
