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

### 1. A crossing is DERIVED: crossable pieces that overlap

Today's model, hardened — with one correction forced by geometry (below):
crossable is a **per-piece flag**, not a dedicated piece id. The crossing exists
wherever two flagged stretches legally overlap. Nothing is stored about the
pair.

- **Rendering: free, and verified.** The editor paints every piece's edge
  decoration before any piece's asphalt, precisely so that asphalt clips paint
  (`EditorRenderer.drawTrack`). At an at-grade crossing each road's asphalt
  therefore covers the other's edge line through the shared zone — the white
  lines stop at the mouths and the intersection reads as a real junction.
  Verified by rendering the eight built-in flattened to one level
  (`CROSSING_PROBE_OUT=… swift test --filter CrossingLookProbe`). The mechanism
  is shape-blind, so it holds for crossing curves too. Kerbs are corner
  treatment and stay on the corners; railings are an elevation feature and an
  at-grade crossing has none.
- **Removal: nothing stored, nothing dangles.** Deleting any involved piece
  opens the ring like deleting any piece; the survivors are ordinary road that
  happens to be flagged crossable, with nothing crossing it. Deleting some
  *other* piece can shift geometry so the overlap moves or turns illegal — the
  validator re-judges from scratch, because there is no stored pair to go
  stale.
- **Switching: a flag toggle, no geometry change at all.** The editor flow
  that avoids the anticipation problem: route road B across road A, and when
  the overlap is detected offer "make it a crossing", which flags every piece
  touching the shared zone — one to three per road, see below — where they
  stand.
- **Encoding: a mode switch, like pitch.** Crossable-ness rides the same
  mechanism as the pitch modes: a byte from the reserved 112–127 block toggles
  the flag for the pieces that follow. A crossing region costs ~2–4 bytes, only
  in tracks that have one. (The dedicated ids 32/33 stay decodable as
  flag-on-straight sugar, but nothing new is built on them.)

#### Why a flag, and why containment-in-one-piece was never viable

Two facts, both checked:

**The straddle is the common case, not an edge case.** Roads are laid in 1U
primitives, and on the axis families every displacement is a whole number of
units — so every piece boundary *and* every centerline sits at whole-unit
coordinates. A 90° crossing's shared zone spans half a road width either side
of the crossed centerline: `[c − U/2, c + U/2]` with `c` whole. That zone is
always **centered on a piece boundary**, covering exactly half of each
neighbouring 1U piece. A single 1U piece can never contain it (that would need
half-unit boundaries the lattice doesn't produce), and requiring containment
would have made 90° crossings impossible to lay. The maintainer's formulation
is the working one: the first piece reaches at least the crossed centerline,
the next clears the road — i.e. the zone is covered by a *run* of crossable
pieces, jointly. (A 2U piece centered on the crossed centerline also works —
its midpoint lands on the lattice — but it is a tidy special case, not the
rule.)

**Curves must cross too.** A figure-eight pinched so the two lobes meet as a
connected `)(` has only curves in the crossing area. Crossable-ness therefore
cannot live in dedicated straight pieces — it has to be a property any piece
can carry, which is what rules out kind-as-id and picks the flag.

Both push the legality rule to where it belongs, **per overlapping sample**
rather than per piece:

> Wherever two stretches of road share tarmac, both must be flagged crossable
> there, and the crossing angle between them must be steep enough (≥ 45°,
> evaluated per overlapping segment pair — arcs are already sampled into
> segments by `RoadProximity`, so this is the check's native granularity).

Runs, straddles and curved crossings all emerge from that without special
cases; the angle bound is what refuses shallow merges and near-parallel
overlaps, which no flag should bless — and it is also what keeps every zone
about a road width across, which is what keeps rendering tractable (see 1b).

Two scope rules complete it:

- **Ground level only, first cut.** Flat pieces produce no rails, so a ground
  crossing has no wall problem at all. Two elevated roads crossing at deck
  height would each throw a rail across the other's lane; supporting that
  means clipping rail generation against the other road's footprint, which is
  real work deferred until someone wants a double-decker junction. The flag is
  simply refused on off-ground pieces until then.
- **Decals stay out of the zone.** When decals land, anything painted on the
  road inside a shared zone is suppressed — the zone is computable from the
  same overlapping segment pairs the legality rule already visits, and the
  angle bound keeps it small.

### 1b. Considered: allow ALL same-height overlap, let gates keep the track

The most radical simplification (maintainer's suggestion, worth recording
properly): no crossing entity at all — overlap at the same height is simply
legal, and the **gates** are what "keep track of the track". Lap semantics
never depended on the road's topology: a lap counts when every gate is crossed
in order, so shared tarmac cannot cheat a lap no matter how it is arranged.
That insight is true and load-bearing in every model here — it is *why*
crossings are safe for racing at all.

As the only structure, though, it under-constrains everything that draws on
the road. The zones stop being small and rare and become arbitrary:

- **Walls.** Flat pieces produce no rails, so ground crossings are safe — but
  two *elevated* roads overlapping at deck height each throw a guard rail
  straight across the other's lane: a barrier in the middle of live road.
  Fixing that means clipping rail generation against every other same-height
  footprint.
- **Kerbs and edge lines** interrupt correctly through a small, steep zone
  (verified by the probe) — but a long shallow merge erases them for its whole
  length, leaving an unfinished-looking smear of pavement.
- **Decals** (the planned direction arrows and friends) get chopped by the
  other road's asphalt mid-glyph, and a direction arrow inside a junction is
  semantically wrong anyway — so decals need suppress-inside-the-zone logic,
  whose cost scales with how large and common zones are allowed to be.
- **The resolver tiebreak dies.** Heading alignment disambiguates a steep
  crossing; in a shallow merge the two roads' headings nearly agree, and
  nothing local can say which stretch a car is on.

So permissiveness is not free — it converts a bounded, deliberate feature into
an obligation on every current and future surface feature. The angle bound in
option 1 is exactly what keeps the rendering problem bounded: zones stay about
a road width across, and only exist where an author meant them.

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

- **The per-sample legality rule above.** `legallyCrossing` is currently a
  blanket, piece-level "any two crossables may overlap anywhere", which would
  bless shallow-angle messes and stacked triples. It moves down to
  `RoadProximity`'s segment pairs: both sides flagged, angle ≥ 45°.
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
  legality rule should keep gate seams out of the shared zone — and this is
  concrete, not theoretical: in the straddle case the seam between the two
  flagged pieces sits exactly at the crossed road's centerline, the dead
  center of the zone, so it is the most natural seam for an author to tap.
- **Cars meeting in the intersection collide.** Already true — contact is
  gated by height and these are equal. That is the feature.

## Decision

**Option 1, with crossable as a flag.** Option 1b's insight is kept — gates
are the reason shared tarmac cannot cheat a lap — but its permissiveness is
not: unbounded zones tax kerbs, walls and every future decal, while the angle
bound makes those problems small, rare and deliberate. It is the least-resistance answer on
every axis asked: rendering is verified free, removal needs no bookkeeping,
switching is a flag toggle with zero geometry change, and encoding rides the
existing mode-switch mechanism. The editor's part (permit crossable overlap
mid-build, plus the "make it a crossing" offer that flags the touched pieces)
folds into the overhaul naturally. The engine work that remains — the
per-sample legality rule and the resolver tiebreak — is the cost of at-grade
crossings themselves, owed under any representation.

Option 2 is the better *object model* in the abstract, but everything unique it
buys is either already free (rendering) or a prerequisite it adds (multi-end
editing), and it deepens the anticipation problem it should have solved.
