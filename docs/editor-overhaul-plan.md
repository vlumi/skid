# Editor overhaul: plan

> **Steps 1–6 shipped** (#95–#108, v0.6); only step 7, the chrome pass,
> is left and it is explicitly decide-on-device. What the editor does *now*
> is [ARCHITECTURE.md](../ARCHITECTURE.md).

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
  palette as pre-decaled pieces that would multiply it.
- **Reversal is a whole-track transform, not a start-line variant.** This plan
  originally routed it through a long-press on the start piece, with the
  compiler honouring a facing flag. Reversing the LAYOUT turned out to be both
  simpler and less invasive: mirror the pieces, run the list backwards, invert
  the pitches. The compiler already derives the centerline, the gate order and
  the grid from the walked pieces, so all three follow for free and nothing
  downstream learns a new concept. It sits with rotate and raise/lower, which
  are the same class of operation.
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

## 6. Reversing the driving direction — DONE

A whole-track button, next to rotate and raise/lower. `reverseDirection()`
mirrors every piece, runs the list backwards and inverts every pitch; the
origin moves to the old ring's last exit, reversed. Gates, fitters and decals
remap with their pieces.

The start line moves to the **other end of the start piece** — it is that
piece's exit by definition (`TrackValidator.gatesValid` keys the finish to that
index), and driving the other way you cross the start piece from its far side.
The grid, the gate order and the centerline then follow the walk with no
compiler change at all.

Refused on an open chain (nothing has settled a direction yet) and on any piece
without an exact mirror — the same exact-or-nothing rule the rest of the model
keeps. `normalized()` deliberately does not normalize reversal away, so the two
spellings stay distinct codes.

**Tested,** each part confirmed by sabotage: the road doesn't move, the track
still validates, the direction flips, the AI laps it, reversing twice is the
identity, it's undoable, an open chain is refused, and grid slots sit behind
the line in both facings.

Still open from this step: a long-press variant picker (for deleting and
reassigning the start line), which reversal no longer depends on.

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
- **The whole of step 7**, widened after device use. In the author's order of
  annoyance: the chrome **covers the track**; the button layout is arbitrary and
  space-hungry; **modes are invisible** (gate mode, rail-new-pieces, level
  filter); and **rails have two controls** — a sticky "rail new pieces" toggle in
  the palette and a per-piece checkbox in the properties sheet.

  The question to answer per control: **action, mode, or property?** Rails are
  the clearest case of that being unmade — the same idea wearing two shapes.

  Note the retro pass missed these: the rail toggles and the piece-properties
  rows are still rounded and native, so restyling rides along with whatever
  reorganization happens.
