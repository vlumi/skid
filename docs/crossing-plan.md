# At-grade crossings: design

What it takes to let two stretches of road share tarmac at the same height —
the bridgeless-8 intersection. This decides the model before the editor
overhaul touches deletion, because "what happens when you delete a crossing"
depends entirely on what a crossing *is*.

Judged on the maintainer's axes: rendering (kerbs/walls around the crossing,
and the eventual decals), removal and switching, encoding — and overall
resistance, engine-side and editor-side.

## The model: crossings are implicit — geometry decides, nothing is declared

**An author never marks, flags or places anything crossing-specific. They draw
a road across a road, and if the geometry reads as a crossing, it is one.**

Concretely, the overlap rule changes from "refuse all same-height overlap" to
a per-sample judgement:

> Two stretches of road may share tarmac where they cross STEEPLY — evaluated
> per overlapping segment pair (the granularity `RoadProximity` already works
> at), with an angle threshold. Shallow overlap — merges, near-parallel runs,
> a road grazing itself — stays refused exactly as today.

Everything else about the feature falls out of that:

- **Removal: nothing stored, nothing dangles.** A crossing is a fact about
  geometry, so deleting any piece just changes the geometry and the validator
  re-judges from scratch. There is no pair, flag or object to go stale — the
  concern that motivated this design work dissolves entirely.
- **Switching: the operation does not exist.** Nothing to convert a piece to
  or from. (The old crossing piece ids 32/33 become vestigial; they stay
  decodable but nothing is built on them.)
- **Encoding: zero bytes.** Nothing to record, nothing for canonical rotation
  to carry.
- **Editor: draw, and it works.** The placement blocking permits what the
  rule permits and refuses what it refuses, same as today — no new controls,
  no "make it a crossing" flow, no anticipation problem. WYSIWYG: an
  accidental steep crossing is a visible, working crossing on screen, which is
  what the author drew.
- **Laps stay honest for free** (maintainer's observation, load-bearing):
  lap semantics never depended on road topology — a lap counts when every gate
  is crossed in order — so shared tarmac cannot cheat a race no matter how it
  is arranged. Gates keep track of the track.

### Rendering: verified, and bounded by the same rule

The editor paints every piece's edge decoration before any piece's asphalt,
precisely so that asphalt clips paint. At a crossing, each road's asphalt
therefore covers the other's edge line and kerbs through the shared zone — the
lines stop at the mouths and the intersection reads as a real junction, with
zero crossing-specific drawing code. Verified by rendering the eight built-in
flattened to one level (`CROSSING_PROBE_OUT=… swift test --filter
CrossingLookProbe`); the mechanism is shape-blind, so it holds for crossing
curves too.

The angle threshold is what keeps this presentable: it caps every shared zone
at roughly a road width across, so interruption stays the correct look. The
fully permissive alternative (below) is where rendering gets hard.

Two scope rules complete it:

- **Ground level only, first cut.** Flat pieces produce no guard rails, so a
  ground crossing has no wall problem at all. Two elevated roads crossing at
  deck height would each throw a rail straight across the other's lane;
  supporting that means clipping rail generation against the other road's
  footprint — real work, deferred until someone wants a double-decker
  junction.
- **Decals stay out of the zone.** When decals land, anything painted on the
  road inside a shared zone is suppressed — mangled half-covered glyphs aside,
  a direction arrow inside a junction is semantically wrong. The zone is
  computable from the same overlapping segment pairs the rule already visits,
  and the threshold keeps it small.

### Why the pieces don't need to "contain" the crossing

Checked on the lattice: roads are laid in 1U primitives, and on the axis
families every displacement is a whole number of units — so every piece
boundary *and* every centerline sits at whole-unit coordinates. A 90°
crossing's shared zone spans half a road width either side of the crossed
centerline, so it is always **centered on a piece boundary**, covering exactly
half of each neighbouring piece. The maintainer's formulation is the working
one — the first piece reaches at least the crossed centerline, the next clears
the road — and the per-sample rule makes it automatic: the zone is covered by
whatever pieces happen to be there, jointly. No containment requirement, no
special sizes.

A figure-eight pinched so the lobes meet as a connected `)(` works the same
way: the crossing area is all curves, and the rule never asks what shape a
piece is. **One number to tune when implementing**: the angle threshold. 45°
is the starting point, but a gently pinched `)(` crosses shallower than a
square junction — measure real pinched eights and set the threshold so they
pass while merges still fail, rather than trusting the round number.

## Rejected along the way

- **A crossable flag per piece** (with "make it a crossing" offered by the
  editor when routing across). The maintainer's verdict is the design review:
  nobody wants to manage flags on track pieces. The flag's only value over
  the implicit rule was distinguishing intended crossings from accidental
  ones — and an "accidental" steep crossing is a visible, working junction the
  author can see and keep or reshape. Ceremony for no gain.
- **Fully permissive overlap, gates as the only structure.** The gate insight
  is kept (above), but unbounded zones tax every surface feature: elevated
  rails across live lanes, kerbs and edge lines erased along whole shallow
  merges, decals chopped mid-glyph — and heading alignment cannot
  disambiguate a shallow merge for the resolver. The angle threshold is
  retained precisely to bound all of that.
- **A crossing as one placeable X piece** (side ports riding the fork
  machinery). Better object model in the abstract, but everything unique it
  buys is either already free (rendering, per the probe) or a prerequisite it
  adds (multi-loose-end editing), and it forces the author to anticipate the
  crossing while building the first road.
- **The piece list referencing a crossing twice** — paired entries or a
  revisiting walk. Breaks list-order = route-order, which seams, gate indices
  and `arcPosition` all rest on; the same reason forks are parked.

## The real work items

- **The per-sample legality rule** replacing the blanket refusal — both the
  permit (steep crossings) and the keep (shallow overlap refused), in
  `RoadProximity`'s segment pairs where the data already lives.
- **Position→road resolution in the shared zone.** `closestCenterlinePoint`
  disambiguates a bridge crossing by height; at the same height that tiebreak
  is gone, so the AI's lookahead and `arcPosition` can snap to the wrong road
  inside the zone. The tiebreak is **heading alignment** — the wrong road is
  steeply off the car's travel, by construction of the legality rule. Unlike
  the mid-ramp resolver quirk, this does not self-correct; it lands before
  crossings ship.
- **Gate seams kept out of the zone.** Gates are directional, so crossing
  traffic scores ~zero along a gate's forward — but a drifting car at a
  shallow angle could tick one. Concrete, not theoretical: in the 90° straddle
  the piece boundary sits exactly at the crossed road's centerline, dead
  center of the zone, and is the most natural seam for an author to tap.
- **Cars meeting in the intersection collide.** Already true — contact is
  gated by height, and these are equal. That is the feature.
