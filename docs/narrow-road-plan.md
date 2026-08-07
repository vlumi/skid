# A narrow road

Not "road widths" in general — one **narrow** variant, used as a bottleneck.
Wider roads are the part to leave alone: there is rarely spare canvas for them,
and a wide road asks nothing of the driver.

The shape of the idea, from the device conversation:

- The centerline is unchanged, so a narrow piece mates and closes exactly like
  its full-width twin.
- Narrowing should be available on **every piece we already have**, not a
  parallel set of narrow shapes.
- It earns its place as a **short bottleneck**. Long narrow stretches are not
  fun with driving this twitchy, and nothing should encourage them.

## What the code already gives us

`Track.width` is **one value for the whole track**, and every question about
where the asphalt ends goes through one funnel:

```swift
func halfWidth(atHeight height: Double) -> Double {
    width / 2 * Elevation.scale(atHeight: height)
}
```

Thirteen call sites across collision, the compiler, the walls, the renderers and
the overlap checks — all of them ask that one function. **Width is also absent
from the share code**: it is a constant of the format version, not stored.

So the work is not "thread a width through the engine". It is:

1. make width a property of a **placed piece** rather than the track, and
2. make `halfWidth` take a position as well as a height.

Everything downstream follows, because everything downstream already funnels.

`docs/track-pieces.md` ("Road width — grip vs. visual") called this shot
already: grip width is **per-port**, sharp steps at a seam are legal, ports mate
on pose alone, and the surface test takes the **wider** ribbon at a joint so a
step never opens a grip gap. That is the model to build; this doc only adds the
sizes and the one piece that has to refuse.

## The size, measured

| | |
|:--|:--|
| road width | **120** (= 1U), half-width 60 |
| car width | **20** |
| car collision radius | **12** |
| grid slots | staggered **±28** from the centerline |

Three candidates, all whole numbers of units so nothing lands off-lattice:

| width | half | grid fits (needs ≥38)? | two abreast? | clearance per side |
|:--|:--|:--|:--|:--|
| **90** (0.75×) | 45 | yes | yes | 35 |
| **80** (⅔×) | 40 | barely | yes | 30 |
| **60** (0.5×) | 30 | **no** | yes (40 needed) | 20 |

**80 is the pick.** It is a visible step down from 120, still lets two cars
through side by side (so a bottleneck is a squeeze rather than a wall), and
leaves 30 units of clearance each side — more than a car's own collision radius,
so a centred car is not scraping by construction.

60 is tempting and wrong: it cannot hold the start grid, and at 20 units of
clearance the twitchiness you already dislike would decide the race.

## The start piece must refuse

**This is the one hard constraint, and it is arithmetic rather than taste.**

The grid staggers cars **±28** from the centerline and a car is 20 wide, so the
outermost car edge sits at **38**. A start piece narrower than a 38 half-width
puts cars visibly off the asphalt on the line — and at 60 wide (half 30) they
would straddle the grass before the flag drops.

So the start grid is **never narrow**, refused in the model rather than left to
the author. That also means "narrow every piece" is not quite the rule: it is
every piece *except* the one the grid sits on.

At 80 the grid does fit (40 ≥ 38), but with 2 units to spare — so the refusal is
about not depending on that coincidence. If the grid stagger ever changes, a
narrow start line should not silently become the thing that breaks.

## Keeping it a bottleneck

The tempting move is a rule capping how many narrow pieces may run consecutively.
Worth resisting: it is a rule the author has to discover by being refused, for a
judgement that is theirs. **The drivability warning is the right home** — it
already exists, it already says "this piece is a problem" without blocking the
track, and "a long narrow stretch" is exactly the kind of advice it should give.

Deferred until there is a narrow road to measure, and until it can say something
specific ("11 narrow pieces in a row") rather than a guess at a threshold.

## Encoding

Width is not in the share code today, so this needs a new section: a **narrow
flag per piece index**, exactly like `railed` (tag 8) — one bit of information
per piece, so one byte per narrow piece and the section omitted entirely when a
track has none. It becomes the **seventh** index-keyed thing every layout
mutation has to remap (`TrackLayoutMutate`), alongside gates, fitters, decals,
rails and warp drops.

A per-port *value* (rather than a flag) is what the track-pieces doc ultimately
wants, for tapers. A flag is the subset that ships now and encodes smaller; the
tag can carry a width byte later without moving.

## What this touches

- **`Track.width` → per-piece.** The compiler already walks placed pieces to
  build the centerline, so it can emit a parallel half-width array exactly like
  `heights`, `deckTops` and `gaps`. That is the established pattern for
  "something that varies along the road", and it means `halfWidth(at:height:)`
  interpolates the same way heights already do.
- **The seam rule**: take the **wider** of two ribbons at a joint, so a step
  never opens a gap the car can fall through.
- **Walls and kerbs** follow the ribbon edge, which they already do via
  `halfWidth` — the flat-`width / 2` sites that caused a session of bugs are
  gone, so this should not resurrect them. Worth a test that pins it anyway.
- **Overlap and proximity** (`RoadProximity`, `RibbonPenetration`) measure
  against a half-width constant today; a narrow road makes previously-illegal
  neighbouring fits legal, which is a feature but needs its own tests.
- **The renderer** already draws from `halfWidth`, so a narrow road draws itself.

## Verification

The usual: `make test`, both linters, `make build-ios`, all by exit code, and
every test sabotaged before it is believed.

The specific traps, given this project's history:

- **Test what is DRAWN**, not just what is modelled. A narrow road that the sim
  grips at 80 and the renderer paints at 120 is precisely the bug class that has
  cost the most here — assert the ribbon geometry, not only `halfWidth`.
- **A seam between widths must not open a grip gap.** Drive a car along the
  edge across a narrow→wide joint and assert it never reads as grass.
- **The start grid stays on the asphalt.** Assert all four slots, not the pole.
