# At-grade crossings: design

What it takes to let two stretches of road share tarmac at the same height —
the bridgeless-8 intersection. The catalog has the pieces (`crossingShort` /
`crossing`, ids 32/33, `kind: .crossing`), the validator permits crossable
pairs to overlap, and the editor's buttons are hidden; the compiler has never
built one. This decides the representation before the editor overhaul touches
deletion, because "what happens when you delete a crossing" depends entirely on
what a crossing *is*.

Judged on the axes that matter (maintainer's list): rendering (railings/kerbs
around the crossing), removal and switching, encoding — and overall resistance,
engine-side and editor-side.

## The options

### 1. A crossing is DERIVED: two crossable pieces that overlap

Today's model, hardened. Each road carries an ordinary straight whose `kind` is
`.crossing`; the crossing exists wherever two of them legally overlap. Nothing
is stored about the pair.

- **Rendering: free, and verified.** The editor paints every piece's edge
  decoration before any piece's asphalt, precisely so that asphalt clips paint
  (`EditorRenderer.drawTrack`). At an at-grade crossing each road's asphalt
  therefore covers the other's edge line through the shared zone — the white
  lines stop at the four mouths and the intersection reads as a real X
  junction. Verified by rendering the eight built-in flattened to one level
  (`CROSSING_PROBE_OUT=… swift test --filter CrossingLookProbe`); no
  crossing-specific drawing exists or is needed. Kerbs are corner treatment and
  crossables are straights, so kerbing stays on the neighbouring corners where
  it belongs. Railings are an elevation feature and an at-grade crossing has
  none.
- **Removal: nothing stored, nothing dangles.** Deleting either member opens
  the ring like deleting any piece; the survivor is an ordinary crossable
  straight with nothing crossing it. Deleting some *other* piece can shift
  geometry so the pair no longer overlaps (fine — no longer a crossing) or
  overlaps illegally (the validator already refuses that as an overlap).
- **Switching: a 1:1 id swap.** The crossable pieces have *identical paths* to
  the plain straights — `shortStraight`↔`crossingShort` (1U),
  `straight`↔`crossing` (2U) — differing only in `kind`. Converting a normal
  straight to crossable in place changes one id and no geometry. That enables
  the editor flow that avoids the anticipation problem: route road B across
  road A, and when the overlap is detected offer "make it a crossing", which
  swaps both ids where they stand.
- **Encoding: zero change.** The ids already encode; there is no pair to
  record; canonical rotation has nothing new to carry.

### 2. A crossing is ONE PIECE: an X with side ports

A single placeable object: one entry, one exit straight through, plus two
perpendicular side ports. The walk's fork machinery nearly covers it — extra
exits already become inlets plus loose ends, and a later chain can mate into
one side and continue out the other via the loose-end stack.

Attractive properties: deleting it is deleting one list entry (both arms vanish,
leaving two open chains — explicit and honest); encoding is one id; the piece
could draw its own X so rendering is self-contained.

What it actually costs:

- The compiled centerline gets the perpendicular arm only as an accidental
  chord between the mate-in and the continue-out; seams and gates on the arm
  are undefined; the walk's LIFO discipline becomes a contract the editor must
  maintain.
- The editor needs multi-loose-end support to build into a side port — the
  hardest part of the overhaul, made a prerequisite.
- The anticipation problem is worse, not better: the X must be placed while
  building the *first* road, or swapped in later — and swapping a mid-chain
  straight for an X whose side ports re-route the walk is exactly the
  mid-track surgery the overhaul exists to make safe.
- Its one unique payoff, self-contained rendering, buys nothing: option 1's
  rendering already comes out correct (see the probe).

### 3. Rejected: the piece list references the crossing twice

Either as two paired entries (reintroduces the cross-reference deletion was
supposed to escape, just explicitly) or as the walk revisiting a placed piece
(breaks list-order = route-order, which seams, gate indices and `arcPosition`
all rest on — the same reason forks are parked). Not pursued.

## What at-grade crossings cost REGARDLESS of representation

These are the real work items, and picking a representation doesn't change
them:

- **A geometric legality rule.** `legallyCrossing` is currently a blanket "any
  two crossables may overlap anywhere", which would bless shallow-angle
  messes and stacked triples. It needs: the shared zone contained within both
  pieces' spans, a crossing angle steep enough (the piece sizing already
  assumes 90° for 1U and 45° for 2U), and at most one partner per crossable.
- **Position→road resolution in the shared zone.** `closestCenterlinePoint`
  disambiguates a bridge crossing by height; at the same height that tiebreak
  is gone, so inside the zone the AI's lookahead and `arcPosition` can snap to
  the wrong road. The cheap correct tiebreak for steep crossings is **heading
  alignment** — the wrong road is 45–90° off the car's travel. (Same family as
  the mid-ramp resolver note on `closestCenterlinePoint`; this one does not
  self-correct, so it must be fixed before crossings ship.)
- **Gates near the zone.** Gates are directional, so road-B traffic crossing
  road A's gate line at ~90° scores ~zero along the gate's forward and doesn't
  count — but a car *drifting* through at a shallow angle could tick it. The
  legality rule should keep gate seams out of the shared zone.
- **Cars meeting in the intersection collide.** Already true — contact is
  gated by height and these are equal. That is the feature.

## Decision

**Option 1.** It is the least-resistance answer on every axis asked: rendering
is verified free, removal needs no bookkeeping, switching is an id swap,
encoding doesn't change, and the editor's part (permit crossable overlap
mid-build — already permitted — plus the "make it a crossing" offer) folds into
the overhaul naturally. The engine work that remains — the legality rule and
the resolver tiebreak — is the cost of at-grade crossings themselves, owed
under any representation.

Option 2 is the better *object model* in the abstract, but everything unique it
buys is either already free (rendering) or a prerequisite it adds (multi-end
editing), and it deepens the anticipation problem it should have solved.
