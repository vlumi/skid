# Height groundwork: rails, embankments, more levels

> **Not started.** Structural work to do *before* new pieces — it changes what
> a ramp means, and every later piece inherits that. What the model does *now*
> is [ARCHITECTURE.md](../ARCHITECTURE.md); the tunnel spec it feeds into is in
> [track-pieces.md](track-pieces.md).

Three things currently ride on one `if` — `PieceCompiler:248`, "is this piece
off the ground" — and they are not the same concept:

| | What it is | Cosmetic? |
|---|---|---|
| **Side rails** | A barrier you bounce off | **Yes** — should be a placement attribute |
| **Embankment sides** | A ramp is solid earth; you cannot enter its flank | No — geometry |
| **Mouth gate** | One-way level seal under the raised end | No — this is the anti-warp rule |

Separating them is half the groundwork. The other half is **vertical**: falls,
jumps and a slide off a banked curve are all one event — the car left the road at
some height — and none of them arc today. That comes first, because every later
step adds another caller for it.

Once both are done, more levels and tunnels are mostly a constant change, and
jump pieces and banked curves are mostly free.

## 1. Ballistic flight — one rule for everything that leaves the road

**First, because everything else inherits it.** Falls off a deck, off a railless
ramp flank, off a banked curve's high side, and off a jump lip are all the same
event: the car left the road at some height and comes down. Build the curve
first and each of those is free; build them first and each invents its own
behaviour, which then disagree.

Today flight is a horizontal glide: `airborneTicks` counts down, `height` is
untouched, and a deck "fall" *snaps* height to 0 and then flies for 8 ticks — so
the car is already at the bottom before it visually lands. There is no arc.

Replace it with a vertical velocity and gravity:

```text
vz -= g · dt
h  += vz · dt
land when h meets the road beneath
```

That makes a jump off a lip, a fall off a deck edge, and driving off a ramp
flank **the same code**. `airborneTicks` stops being a timer and becomes a
consequence — flight ends when the car meets a surface.

**Landing is whatever is beneath you.** Launch from the ground onto a deck; fall
from a height-2 deck onto one at 1. This is what makes jumps interesting rather
than decorative, and it is exactly step 4's floor-detection seen from the other
side, so the two want doing together.

### Two numbers, measured

**Apex is small, and should be.** At `vz = 1.0` and the gravity that preserves
today's flight time, the car peaks **0.12 levels** above the lip — a twelfth of
a bridge. That matches "not far above", and is small enough that the existing
scale-up-when-airborne render cue is what actually sells it.

**Watch the speed gate.** Today distance is *quadratic* in speed — 243 units at
520, but only 80 at 300 — a strong "be fast or fall in" rule. With a FIXED
launch `vz`, flight time is speed-independent and distance goes linear: 138 at
300. The jump gets much easier to clear.

Fix by **scaling launch `vz` with speed**, which restores the quadratic and is
more honest anyway: a faster car launches harder.

### Rails clip a flying car

`collideWithWalls` runs while airborne, and `blocks` compares `car.height` to
wall height. A car flying at height 1 passes over ground rails but **hits deck
rails at 1** — including the landing piece's own. A jump's flight corridor
probably wants rails off the pieces it crosses, which is step 3's attribute
doing real work rather than cosmetics.

## 2. Embankments occupy `[base, top]`, not `[0, top]`

The anti-warp rule is sound and should not change: the mouth gate is **a height
test, not a direction test** — *you must effectively be of the upper level to
pass*, at `level − reachTolerance`. It does not care where you approach from,
which is what makes it robust.

What is wrong is the assumed base. A ramp is walled as if it rises from the
**ground**, because today every ramp does. A **1→2 ramp stands on the deck**, so:

- its flanks must block cars at height **1**, not 0;
- a ground car at 0 passes **underneath it freely** — the deck it stands on is
  already the roof;
- its mouth gate is `2 − reachTolerance`, which the current code already gets
  right (it reads the mouth's own height).

**The validator is already general** — `RoadProximity.solidFloor` is `trunc(h)`,
so it already treats a 1→2 ramp as occupying `[1, 2]`. Only the wall emission
assumes 0. That is the whole fix, and it is currently invisible because no ramp
starts above the ground.

This is the same solidity-interval rule the tunnel spec states (cuttings occupy
`[h, 0]`), so generalizing here is a prerequisite for tunnels too.

## 3. Embankment flanks are ONE-WAY

You may drive **off** a ramp's side; you may not drive **into** it. Today the
flanks are `.rail` — symmetric — so a railless ramp would still trap you on it.

This holds for **every** ramp, railed or not. A railed ramp's rail stops you
because a rail is a barrier; the embankment underneath is one-way regardless.
That keeps rails purely additive rather than secretly structural — a cosmetic
attribute must not change what the ground is.

Needs a new `Wall.Kind`, alongside the `cuttingRail` the tunnel spec already
plans; both are one-way walls, so they likely share an implementation. The side
test is the sign of the cross product against the wall's stored direction, and
`Wall.outward` already exists and is already emitted deliberately (it *cannot*
be derived — see its doc comment).

Driving off a flank then *falls* — which is step 5, where a fall stops being a
fixed 8 ticks and becomes gravity acting on the height lost.

## 4. Rails become a placement attribute

`hasRails` per piece, defaulting to off-ground so existing tracks are unchanged.

Unlocks both directions the roadmap wants: **bridges without railings** (drive
off the edge — the fall path already exists) and **railings on flat pieces**.

Encoding: one bit per piece. Cheapest home is the existing pitch/attribute
section rather than a new one.

## 5. `highestLevel = 2`

One line — the level vocabulary was built for it (`TrackLevel.swift` says so).
Safe only **after** step 2, or a 1→2 ramp walls off the ground beneath it.

**The real bound is the canvas, not the model.** `Pitch` climbs half a level per
piece, so height 3 needs six pieces of pure climbing — 1440 units of a 1600-wide
canvas, just to get up. Height 2 is comfortable; **3 is a curiosity until track
size classes land**.

## 6. Tunnels (`lowestLevel = −1`)

The spec in [track-pieces.md](track-pieces.md) is thorough and its structure is
decided; what is open is mechanics, and it carries the **camera problem** as a
stated prerequisite — a top-down view has to decide what to draw over a buried
car.

Reuses everything above: the same interval rule, the same one-way walls. Do it
last, and only after the camera question has an answer.

## Order, and why

1. **Ballistic flight** — every later step produces a new way to leave the road,
   and they must all fall the same way. Cheapest to make one rule before there
   are three callers to reconcile.
2. **Embankment `[base, top]`** — invisible today, and more levels depend on it.
3. **One-way flanks** — the wall model becomes directional, which tunnels also
   need. Now falls off a flank already work.
4. **Rails as an attribute** — purely cosmetic once structure has moved out.
5. **`highestLevel = 2`** — safe once ramps know what they stand on and falls
   know what they land on.
6. **Tunnels** — after the camera question.

Then jump pieces and banked curves, both of which are mostly free by that point:
a jump is a lip that sets a launch velocity, and a bank's high-side slide is a
fall with a sideways kick.

Steps 1–3 are the ones worth doing carefully. Ballistics changes how every
existing fall feels, and 2–3 are invisible in the current catalog — a mistake
there shows up only once a 1→2 ramp exists, by which point tracks may depend on
the wrong behaviour.
