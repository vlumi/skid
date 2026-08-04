# Height groundwork: flight, rails, embankments, the fence

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

The **boundary fence** (step 6) is independent of all of it and can go any time —
it is in here because it is the other thing that decides what happens when a car
leaves the road.

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

**Shipped (#127).** Gravity 18, launch kick 0.004/speed, both in the Tuning
panel under *Air*. **Not yet judged on device**, deliberately: every deck is
railed today, so nothing can actually fall — the change is dormant until step 3
and step 4 make railless pieces possible. Tune it then, when it is reachable.

## 2. Embankments occupy `[base, top]` — ALREADY CORRECT

**Checked, and the fix is not needed.** The plan assumed the wall emission
hardcoded a ground base. It does not:

- each rail takes **its own sample's height**, so a 1→2 ramp's flanks sit at
  1.0…2.0;
- `Race.blocks` derives the floor as `wall.height.rounded(.down)`, so a rail at
  1.4 blocks 1.0…1.4 and a ground car passes underneath;
- the mouth gate already reads the mouth's own height, and a gate hangs exactly
  one storey — so an upper mouth lets the ground pass beneath it.

Verified by probe and pinned by `RampBaseTests`, which fail if the floor is
hardcoded to 0. The tests are the deliverable here: the behaviour is invisible
until ramps above the ground are buildable, so it needs guarding before then
rather than fixing.

## 2b. Banking is an ATTRIBUTE, like pitch — not new shapes

A banked curve has the **same centerline, ports and closure arithmetic** — it
only tilts, which is the definition of an attribute rather than a shape. The
docs already made this call for pitch: *"the catalog stays a set of SHAPES, and
'ramp' stops being a thing you pick and becomes a way you lay road."*

As ids it would be a cross-product: 46 curve-ish catalog entries × pitch × bank.
As attributes they simply coexist — **a curved ramp is already shape + pitch, so
banking is a third independent axis**, and a banked climbing curve falls out for
free. Pitch tilts along travel, bank tilts across it; they never interact
geometrically.

**Chaining copies pitch exactly.** `height(atFraction:)` eases within a piece, so
consecutive ramps blend into an S without either knowing about its neighbour.
`bank(atFraction:)` on the same shape: a piece's entry bank is its predecessor's
exit, so three banked curves stay banked and a following flat piece flattens
across its own length. No seam special-casing.

**One place the analogy stops:** pitch is a *direction* (`.up`/`.down`) because
the amount is fixed at half a level. Banking wants a **magnitude** as well — a
gentle lean is not a wall of death — so its attribute is richer than pitch's.

**Rendering reuses the shading already there.** Height reads as brightness
today — `fillRoad` shades a ramp from its entry shade to its exit shade, and a
road resting at 0.5 takes the matching mid shade, so a split climb reads as one
continuous surface. Banking is the same scheme on the perpendicular axis: pitch
shades **along** the piece, bank shades **across** it, so a banked climbing
curve is naturally a diagonal gradient. No new visual language, and the height
cue stays consistent with every other piece.

## 3. Embankment flanks are ONE-WAY — DONE

The anti-warp rule is sound and should not change: the mouth gate is **a height
test, not a direction test** — *you must effectively be of the upper level to
pass*, at `level − reachTolerance`. It does not care where you approach from,
which is what makes it robust. What changes is only the **sideways** rule.

You may drive **off** a ramp's side; you may not drive **into** it. Today the
flanks are `.rail` — symmetric — so a railless ramp would still trap you on it.

**Done, after two false starts. The lesson: a rail and an embankment are two
WALLS, not one wall with a flag.** A climbing piece currently emits a single set
of edge walls doing both jobs, and adding `oneWay` to them made *every* rail on
a ramp one-way — 128 of 136 on the eight, which is mostly climbing pieces — so
you could drive through railings almost anywhere. A rail is a symmetric barrier
and cosmetic; an embankment is one-way and structural. **They must be emitted
separately**, which is work step 4 needs regardless: a railless ramp is
impossible until the two are distinct objects.

Two things that attempt also proved, worth not rediscovering:

- **"Was the car on road?" is the wrong side test.** It is true of the
  legitimate driver too, so it opens the barrier for exactly the person it
  should hold in.
- **The nearest wall's `outward` is also wrong.** A flank is a chain of short
  walls along a curve, so it answers "which side of this SEGMENT", a different
  question.

The side test wants to be about the RAMP, and cheaply — a per-wall centerline
search took the suite from 36s to 47s, which is the cost this file already warns
about.

Needs a new `Wall.Kind`, alongside the `cuttingRail` the tunnel spec already
plans; both are one-way walls, so they likely share an implementation. The side
test is the sign of the cross product against the wall's stored direction, and
`Wall.outward` already exists and is already emitted deliberately (it *cannot*
be derived — see its doc comment).

Driving off a flank then *falls*, which step 1 already built: gravity acting on
the height lost, landing on whatever is beneath.

### Two cosmetic glitches at a ramp's low end — deferred

Both found on device once the railing held; **neither affects physics**, and the
drag itself behaves (you keep sliding, the car just changes where it is drawn).

**1. The blocking face switches from rail to embankment partway down.** From
outside, low on a ramp, the car first stops against the railing's *outer* edge
and then against the embankment. Expected, given the two-wall split: a rail is a
line in the model but a band on screen, so `outboardThickness` adds `kerbBand`
to it, while an embankment has no such band. Where the two overlap in height the
car's stopping distance therefore steps by that band width. The fix, if wanted,
is for the embankment to carry the same outboard thickness as the rail it shares
an edge with — not to remove the rail's, which exists because the car otherwise
halts in mid-air short of the drawn barrier.

**2. The car and its window clip from under the wall to over it at height 0.5.**
`carStorey(of:on:)` bins a car by the storeys its body touches, but every body
corner is rejected by the on-road `guard` when the car is off road on the grass —
so it falls through to `Track.level(of: state.height)`, which **rounds**. An
off-road car beside the ramp's low end therefore jumps from storey 0 to 1 the
instant its height passes 0.5, and the paint order flips with it. Reported as
"the car (and the window) are hidden under the wall, but at some point they clip
above the wall".

The honest fix is for the off-road fallback to ask what is actually *beneath* the
car rather than rounding its own height — the same question `deckTop(at:)` already
answers for the on-road case. Worth doing alongside step 5 (`highestLevel = 2`),
which adds more such boundaries: with three storeys the same rounding flips at
0.5 and 1.5.

## 4. Rails become a placement attribute — DONE

`hasRails` per piece — **defaulting to OFF**, and existing tracks simply lose
their railings until an author toggles them back on. Decided rather than
inferred: a default that reproduces today's look would mean the encoding has to
distinguish "no toggle recorded" from "toggled off", and there are few enough
tracks that adding rails back by hand is cheaper than carrying that ambiguity.

Toggled on an already-placed piece, like a decal — not chosen at placement
time — so the editor gains a rails mode rather than doubling the palette.

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

## 6. The boundary fence: too tight, and one-way

Two separate faults, both reported from play.

### It only blocks crossings, so a car outside stays outside

Measured: a car placed at x = −40 on the bridge ring **never comes back**, and
one driving outward from there reaches −206 and keeps going. `crosses` is a
segment test, so the fence stops you *passing through* — it has no opinion about
a car that is already out. Anything that can displace a car past the line (a
push-out from car contact, a wall bounce at a corner, a fall landing) leaves it
permanently in the void.

The fix belongs with the wall response, not the fence: **a boundary should also
push an outside car back in**, the same overlap-based push-out that
`collideWithWalls` already does for rails. That makes the fence a region rather
than four lines.

### It is built from the drawn footprint, not the canvas

`boundaryWalls(size:)` is called with `bounds.size` — the re-framed footprint,
padded by half a road plus the kerb band. That padding exists to contain what is
*drawn*, and was never meant as a play margin. Measured grass between road edge
and fence:

| track | fenced size | grass on each side |
|---|---|---|
| small | 1320 × 1080 | 120 |
| oval | 1800 × 1320 | 120 |
| **eight** | **654 × 1332** | **27** |
| **clover** | 1134 × 1134 | **27** |

A car is 24 units wide, so the eight and clover give **barely one car's width**
before the wall — which is exactly the "the walls help you round the curves"
complaint. The older two get 120 only incidentally, because their layouts happen
to sit further inside their own bounding box.

And the eight is fenced at 654 wide inside a **1600-wide canvas**, throwing away
946 units of space that is already paid for.

**Fence the canvas, centre the track in it** — the fence becomes "the edge of
what you can see", which explains itself to a player. Going wide then costs time
on grass instead of bouncing you back onto the racing line.

The canvas is **1600 × 1333 in a FIXED orientation** — not an aspect ratio, and
deliberately not rotatable. The track sits between the players, so
portrait/landscape means nothing there; a tall track is simply built sideways.
(The doc calls this "the ~1.2:1 taller-aspect convention", which reads like an
aspect rule and isn't one.)

One guard is needed. The validator measures the **centerline** extent, while
`Track.size` is the **padded** footprint — so a legal track can have padding
sticking out past the canvas, and a naive canvas fence would put walls *inside*
what is drawn. `oval` is exactly this case. So:

```text
fence = max(canvas, footprint + 2·MIN),  centred on the footprint
```

with `MIN` around 60 (2.5 car widths) — **provisional**. The canvas itself is
only half-derived (its aspect is the four-player SE viewport; its scale is a
round-ish guess at 13.33 × 11.11 U), so the margin and the canvas want settling
together rather than tuning one against the other. See track-pieces.md.

Measured against today:

| track | footprint | fence | grass x / y | today |
|---|---|---|---|---|
| small | 1320×1080 | 1600×1333 | 140 / 126 | 120 |
| oval | 1800×1320 | 1920×1440 | 60 / 60 | 120 |
| **eight** | 654×1332 | 1600×1452 | **473** / 60 | **27** |
| **clover** | 1134×1134 | 1600×1333 | **233** / 99 | **27** |

The two tight tracks gain most, which is the complaint. `oval` loses a little on
paper but was never the problem, and 60 is still 2.5 car widths.

Note this splits two numbers that are currently one: the fence wants the canvas
while the **camera** still wants the footprint (reporting the whole canvas as
`Track.size` drew every piece-built track tiny and shoved into a corner — see
`PieceCompiler.framed`).

**The eight is a useful shape, not a broken one.** Its extent is 1332 against a
1333 canvas — one unit from the limit — and it is the tightest-fenced track at
27 units of grass. Both make it the fixture that catches this class of bug,
which is exactly what an unfinished built-in is for. Keep it awkward; do not
"fix" it into the middle of the canvas.

## 7. Tunnels (`lowestLevel = −1`)

The spec in [track-pieces.md](track-pieces.md) is thorough and its structure is
decided; what is open is mechanics, and it carries the **camera problem** as a
stated prerequisite — a top-down view has to decide what to draw over a buried
car.

Reuses everything above: the same interval rule, the same one-way walls. Do it
last, and only after the camera question has an answer.

## Order, and why

1. **Ballistic flight** — ✅ shipped (#127). Dormant until something can fall.
2. **Embankment `[base, top]`** — ✅ already correct; pinned by tests instead.
3. **One-way flanks** — the wall model becomes directional, which tunnels also
   need, and it is what makes a railless ramp drivable rather than a trap.
4. **Rails as an attribute** — purely cosmetic once structure has moved out.
   Together with 3, this is what finally makes step 1 reachable.
5. **`highestLevel = 2`** — safe now that ramps block from their own base.
6. **The boundary fence** — independent, can go any time.
7. **Tunnels** — after the camera question.

Then jump pieces and banked curves (2b), both mostly free by that point: a jump
is a lip that sets a launch velocity, and a bank's high-side slide is a fall
with a sideways kick.
