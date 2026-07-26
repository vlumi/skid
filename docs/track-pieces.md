# Track pieces & the sharing format

The design for v0.6's track editor: a track is an **ordered ring of catalog
pieces** snapped **port-to-port**, always-valid by construction, compiling to
the unchanged runtime `Track` — and small enough that any design travels as a
short URL (and comfortably inside a QR code). This is the settled design;
numbers marked *(v1)* are expected to be tuned once everything is wired up.

Build order (settled): **model first, headless** — catalog, port-snapping,
validity, compile-to-`Track`, encode/decode — as pure logic with tests,
before any editor UI. The acceptance test for the model is the forcing
function: **the catalog must be able to rebuild Hairpin and Overpass**. If it
can't, players can't build anything interesting either.

## The model

### Ports and the ring

A **piece** occupies road between **ports**. A port is a pose: position,
heading, and road width. Pieces carry their geometry in a local frame;
placing a piece means setting its entry port onto the current pose, and its
exit port becomes the next pose. Most pieces have two ports; **fork and join
pieces have three** (see "Beyond the ring"), making the track in general a
**directed port-graph** — but it is still stored as a **flat ordered list of
piece ids** walked from an origin pose, with a small stack discipline
resolving branches. The fork-free case is a plain ring that **closes** when
the walk's final pose equals its starting pose exactly.

- **Headings quantize to 8 directions** (45° steps), stored as an integer
  0–7. Diagonals are first-class, not grid-cell approximations.
- **Width is one global constant in v1** (120 units — the shipped tracks use
  110–130), so all ports mate trivially. The decided evolution ("Road width —
  grip vs. visual" below): per-port grip widths with legal sharp steps at
  seams — ports still mate on pose alone, so it never changes the walk.
- The walk direction **is** the driving direction.

### Exact coordinates — why and how

45° geometry produces √2 offsets, so float positions plus an epsilon would
make "did the loop close?" fuzzy and tolerance-tuned — the opposite of this
codebase's determinism rule. Instead, every reachable position is represented
**exactly**:

```
coordinate value = (a + b·√2) / 2      with a, b ∈ Int
```

Straights of integer length and arcs of integer radius, at any of the 8
headings, always land on coordinates of this form (the 45°-rotation matrix
entries are 0, ±1, ±√2/2, and the ring of such pairs is closed under those
products and sums). Closure and port-mating are **exact integer equality** —
no epsilon anywhere. Floats appear only at compile time, when poses are
lowered to `Vec2` for the centerline.

**Exactly one pose is stored: the origin** — piece 0's position and heading
on the canvas. Every other coordinate is *derived* by walking the piece
sequence from it; the exact type above is the arithmetic the walk uses, not
data that persists. Storing the origin (instead of normalizing it away) is
what lets the author **move and rotate the whole structure on the map** —
one anchor edit, everything follows — which matters once decorations are
placed around the track. The **canvas is a fixed constant of the format
version** (the content-convention track size), so a shared code lands
exactly where its author put it.

### The unit system — sizes that always mesh *(settled 2026-07-24)*

Every length and radius in the catalog is an integer multiple of one **base
unit U = the road width = 120**. Integer dimensions are automatically exact
on the `(a + b·√2)/2` lattice, so the unit system is purely about *meshing*:
whatever the author builds, mismatches are whole units, never stray
fractions.

- **Straights: 120 / 240 / 480** — a doubling family.
- **Curve radii (to road center): tight 120 · medium 240 · sweep 480** — the
  same 1:2:4 doubling. The tight curve's inner edge sweeps at 60: a real
  arc, not a pivot point. Each radius gets 45° and 90° pieces (L/R);
  180° hairpins for tight and medium.
- **Ramps, start grid, jump: 240.** Crossable straights: **120** (90°
  crossings) and **240** (any angle). Fork branches: radius 240.

Radii measure to the **centerline**; the ribbon's ±60 hangs outside it
everywhere — a full tight circle spans 360 = 3U outer, and a U-turn's outer
span is `2r + W`, always an odd multiple of U. Footprints stay U-quantized
because W = U.

**What the grid guarantees.** In the axis-aligned world (straights, 90°s,
hairpins, jogs) every port lands on a U-grid: two loose ends that should
meet are off by whole-U steps, always fixable with straights and detours.
Diagonals extend the same guarantee in a second currency: every reachable
position is `(a + b√2)/2` with *both* components in whole U — a gap is
always "j U axis + k U diagonal", never a hair. The catch: axis straights
only repay the rational part; **√2-debt is repaid only by diagonal travel**.
**Axis and diagonal travel are incommensurable, by construction.** A straight
of integer length `L` on a diagonal heading displaces `L·√2/2` per axis; for
that to equal a whole unit you would need `L = U·√2`, which is not an integer
— so no choice of "diagonal straight length" makes the two grids mesh. This
isn't a gap in the catalog: integer lengths are exactly what make closure
exact integer equality, and any √2-scaled length would trade that for
epsilon-fuzz. Diagonal travel composes perfectly with *itself* (two 1U
diagonal runs at right angles land on a pure axis offset, exactly), which is
why the working rule is about cancelling, not converting.

The rules that keep a build solvent:

- two same-radius 45s in succession = a 90 (debt-free);
- **45s must cancel across the loop**: opposite-handed pairs, or a symmetric
  set all the way round. Eight same-handed 45s (an octagon) cancel; **two do
  not** — a loop of `45R · 90 · 90 · 90 · 45R` turns a full 360° and still
  cannot close *at any straight length*, because both 45s push the same way.
  Adding one more 45 makes such a gap worse, not better;
- opposite sides must match. A regular octagon closes; so does a stretched
  one (long/short/long/short) as long as each side equals its opposite.
  **Watch the start piece**: it is 2U and occupies one of the legs, so an
  octagon of 1U legs is short by exactly the difference — matching the legs to
  the start piece (2U, or 2×1U) closes it. That mismatch shows up as a pure
  *axis* gap, which straights fix;
- an S-chicane's *lateral* shift cancels against its mirror, but each chicane
  also advances `r√2` **forward**, and those accumulate — so a mirrored pair
  gets you back on line without closing the loop by itself.

Symmetric layouts do this bookkeeping automatically — the classic
**figure-8 with diagonal roads** (two mirrored lobes crossing at 90° on
diagonal headings) composes and closes exactly. The editor enforces
exactness at mate time regardless (integer equality), and the **gap readout**
on the selected loose end reports the two components separately — "Gap 2U E +
1U diagonal" — plus which *edit* is needed: straights for an axis gap, turns
for a heading, or "45s must cancel" for a stranded √2 debt (the one case
adding length can never fix).

**Bridging the radii.** Two S families fall out of the system:

- **S-chicane** (45L+45R as one piece, per radius): lateral shift
  `r(2−√2)` ≈ 70 / 141 / 281 — the flow piece; off-grid, pairs to close.
- **Lane jog** (90+90 compound, arcs `r_a` + `r_b`): lateral shift = advance
  = `r_a + r_b` — fully grid-clean. A 2×tight jog (240) re-lines a sweep
  corner as a medium; a tight+medium jog (360) re-lines a sweep as a tight.
  The one hole — a 120 jog (medium↔tight) — has **no** clean single piece
  (it would need r = 60 arcs, below the tight minimum) and is absorbed with
  a detour instead; deliberate, not an oversight.

### Road width — grip vs. visual *(decided; lands after the size pass)*

Width splits into two properties. **Grip width** is the asphalt the car
grips — physics, collision, and what the elevation factor scales. It is
**per-port** (entry/exit), equal on every v1 piece (120). A future taper
piece may carry entry ≠ exit (width lerps along the piece, exactly like
height across a ramp), but tapers are optional sugar: **sharp width steps at
a seam are legal** — ports mate on pose alone, and the surface test takes
the wider ribbon at a joint so there is never a grip gap. **Visual width**
adds the kerb band *outboard* of the grip edge: the kerb is paint, not
surface — it never eats asphalt, counts as asphalt if touched (no slowdown,
no barrier), and grass begins only past it. Deck guard rails are the
opposite: real barriers, never decals.

**Overlap is measured on the asphalt only** *(decided)*. Two ribbons may not
pave over each other, but their kerbs **may abut or share space**: roads
exactly 1U apart are legal and read as a shared kerb between them — a real
track feature, and the tightest fit the unit grid naturally produces (a
hairpin's legs land exactly there). Requiring kerb clearance would outlaw
those fits.

That licence comes with two hard rules for the kerb pass, since paint is the
thing that has to give way:

- **A kerb never covers another piece's asphalt.** Drivable surface has
  priority over decoration, always — so the kerb band is *clipped* by every
  other piece's ribbon, not merely "drawn to fit". A kerb that spilled onto a
  neighboring road would read as a barrier across a racing line.
- **Overlapping kerbs merge into one.** Where two bands would occupy the same
  strip, they must render as a single shared kerb rather than two competing
  ones (double-drawn dashes at conflicting phases look like damage). The
  natural implementation is to build the kerb geometry for the whole layout in
  one pass — union the bands, subtract all asphalt — instead of per piece,
  which is also what makes per-edge styling tractable.

This matters most on a curve's outer edge, where the band is widest and tight
fits are commonest.

### The editing model — one chain, geometry always derived

Editing works like laying rollercoaster track: the start line goes down
first, then the layout **extends piece by piece from a loose end**, in any
of the 8 directions the catalog allows, until every end has met its match —
the fork-free loop simply closes back onto the start line. Fork pieces mean
there can be **several loose ends open at once** (held as a stack; see
"Beyond the ring"); a loose end that lands exactly on an open inlet
**auto-mates** — exact arithmetic makes "exactly" unambiguous. The editor's
state is the same ordered piece list the share code carries — never a set of
placed objects.

Because position is derived, **fragments are unrepresentable** — a piece's
location exists only through its predecessors. That makes mid-chain edits
safe and well-defined:

- **Delete a middle piece** → it leaves the sequence and the tail re-derives
  from that point (visually, everything downstream *swings* into its new
  pose). Always exactly one chain; never two stranded halves.
- **Insert or replace in the middle** → same rule. Swapping a left-hander
  for a right-hander pivots the whole tail — which is exactly how you steer
  a nearly-closed layout the last few degrees home.
- **Delete from a closed ring** → the loop reopens into a chain with a loose
  end; it's simply unsaveable again until re-closed.
- **Move / rotate the whole structure** → edit the *origin pose* (drag to
  translate on a coarse snap grid, rotate in 45° steps). Nothing else
  changes; the layout slides around the canvas as one rigid thing — how the
  author makes room for decorations later.

The editor should *preview* a pending mid-chain edit (ghost the swung tail
before committing) so the pivot never surprises — a UI nicety, not a model
concern. Undo/redo is trivially a list-operation history.

### Height, ramps, bridges

Pieces don't carry an absolute elevation. Elevation is one continuous
**height** scalar (0 = ground, 1 = deck): a ramp piece carries a height
delta (±1), the walk threads entry/exit heights through the chain, and
height rises across a ramp with **smoothstep** easing. There is no stored
integer layer — where the runtime needs one it is *derived* from height.
Closure requires height 0 back at the start line. Same-height overlap is
invalid; **different-height overlap is what makes a bridge** — the whole
Overpass trick falls out of the model for free.

Everything visual is `f(height)` — road width, car scale, ramp wedge,
shadow, z-order — through one live-tunable factor (`Elevation.deckScale`,
slider in Tuning; default 1.2). **True geometry never scales with height**:
centerline radii, lengths, and port poses are identical on deck and ground —
the deck widening is pure rendering — which is exactly what keeps deck and
ground pieces mating on the same lattice. The same primitive extends to
jumps (height rises and falls with nothing beneath) and, someday, the
vertical loop.

### Beyond the ring — forks, crossings, jumps

The ring is the simplest valid track, not the only one. Three families
extend it:

**Forks and joins.** A fork piece has one entry and two exits (three shapes:
straight + branch-L, straight + branch-R, symmetric L/R; sweeper-radius
branches); a **join is the mirrored piece** — two entries, one exit —
a separate id because pieces are directional (the walk *is* the driving
direction). With forks the track is a directed graph and the sim gains
genuine **route choice**. The flat piece list still serializes it: pieces
extend the *current* loose end; a fork's branch exit is **pushed** as a
pending end; when the current end auto-mates into an open inlet, the next
pending end **pops** and continues. Decode is deterministic; no port
references appear in the encoding. Geometry still derives entirely from the
walk, and fragments stay unrepresentable — every branch hangs off the start
piece. **Three-way forks are deliberately out**: two alternative routes at a
time is the ceiling.

**At-grade crossings (the bridgeless 8).** A + crossing is *not* a fork — no
route choice happens there; the lap just drives through the same pavement
twice. So it needs no multi-port piece: a **crossable straight** is an
ordinary straight *allowed* to overlap exactly one other crossable straight
when their midpoints coincide. At 90° the shared zone is one road-width, so
the **150 length suffices**; at 45°/135° it stretches to ~width/sin 45° ≈
170, so diagonal crossings need the **300 length**. The compiler clips the
edge walls at the shared mouths; the ring stays a single closed loop.

**Jumps with air.** The jump piece is a launch lip, a road **gap**, and a
landing. Flight is speed-scaled (the existing launch model, minus the layer
flip), so clearing the gap is *earned*: undershoot drops you onto whatever
is beneath — grass by default, or **a crossing road laid under the gap**,
which the overlap rules explicitly allow. No new fail state; landing short
is slow, not game over.

**Gates with routes.** Every possible lap route must cross the marked gates
in the **same cyclic order** — so gates naturally live on trunk sections all
routes share. Validation enumerates the routes (two per fork, so the count
stays small under the 64-piece cap) and rejects ambiguous placement.

**Staged implementation** — the format reserves everything now, the engine
grows into it:

- *Phase A — ring + crossings + jumps.* The runtime `Track` keeps its single
  closed centerline (a crossing is the ring overlapping itself; a jump is a
  road-less span). Compiler work: wall clipping at crossing mouths, the
  no-flip launch.
- *Phase B — forks.* The runtime `Track` learns multiple routes (a ribbon
  graph), wall handling at fork mouths, and the AI learns to pick a branch.
  The headless model handles the full graph from day one; the Phase-A
  compiler simply rejects fork pieces as not-yet-supported.

## Catalog *(v1)*

One byte per piece id; the id space is an **append-only registry** — ids are
never renumbered or reused, so old share-codes keep decoding forever. New
pieces (and whole new families) are added by appending ids.

Every dimension below is on the unit system (U = 120). Nothing outside the
catalog hardcodes an id — callers use the named `PieceCatalog.ID` constants,
so ids stay data and can be reshuffled until the format's first public
release.

| id | piece | notes |
|---:|---|---|
| 0–2 | straight 120 / 240 / 480 | 1U / 2U / 4U |
| 3–8 | curve 45° · L/R × tight/medium/sweep | radii 120 / 240 / 480 |
| 9–14 | curve 90° · L/R × tight/medium/sweep | convenience (= two 45s) |
| 15–18 | hairpin 180° · L/R × tight/medium | a sweep U-turn would span 9U |
| 19–24 | **S-chicane** · L-then-R / R-then-L × 3 radii | two chained 45s; shift r(2−√2), pairs to close |
| 25–28 | **lane jog** · L/R × 240 / 360 shift | two chained 90s; grid-clean radius bridges |
| 29 | ramp up (straight 240, height +1, launches) | |
| 30 | ramp down (straight 240, height −1) | |
| 31 | **start grid** (straight 240, hash-marked slots, start line at exit) | exactly one per track |
| 32–33 | **crossable straight** 120 / 240 | at-grade crossings: 120 = 90° only, 240 = any angle |
| 34–36 | **fork** · straight+L / straight+R / symmetric L·R | one entry, two exits; radius 240 |
| 37–39 | **join** · mirrors of the forks | two entries, one exit |
| 40 | **jump 240** (launch lip · gap · landing) | gap may be crossed beneath |
| 128–130 | straight 120/240/480 **+ direction arrow** | decal variants, two-byte range |

A piece's path is an ordered **chain** of segments (one chain per exit, two
for a fork), which is what lets a single id bend twice: a chicane is two 45°
arcs, a jog two 90s. Most pieces are a one-element chain.

Still deliberately small — a phone-browsable palette — and designed to grow:
lengths/radii are plain integer parameters, so variants are new ids, not new
machinery. Expected later families: wider/narrower roads (the width model
above), themed surface patches, more decals.

**The start grid** paints its four slots on the pavement as hash marks across
each slot's front edge, at exactly the positions the compiler places cars
(`PieceCompiler.Grid`) — the same markings in the editor and in the game. The
grid is ~220 deep, which a 240 start piece clears; a test asserts the two
numbers stay compatible.

**Decals vs. decorations vs. hazards.** Three categories, split by *what
they touch*:

- A **decal** is painted **on the road**, is part of a piece, and **never
  touches physics** — same geometry, different look, so it's simply another
  catalog id (the direction-arrow straights above; later: painted kerbs,
  surface markings).
- A **decoration** lives **beside the road** (trees, buildings, signs),
  visual only, freely placed — its own future encoding section, not catalog
  ids.
- A **hazard** (oil, water, mud) is a **surface patch: it changes physics**,
  so it's neither of the above. It places freely like a decoration (baking
  oil-slick variants into every piece × position would explode the id space
  and still couldn't put the slick exactly at an apex) but from a small
  catalog of rough, rotatable blob shapes at quantized positions — so the
  sim stays deterministic. Its own future section, validated against the
  road footprint.

## Start, grid, and gates

- The **start-grid piece** (id 18) carries the whole start: a straight long
  enough for the four-car grid (~220 of depth plus car length), the grid
  markings as its decal, and the **start/finish line at its exit port**.
  Every track contains **exactly one**; it's the first thing the editor
  places and the one piece that can't be deleted (the layout moves via the
  origin instead).
- The ring is **stored cut at the start line**: the start piece is the last
  element, so **seam 0** (the joint before piece 0) is the start/finish, and
  the **stored origin is literally the start line's pose**. Start slots
  compile via the existing `TrackCompiler.startGrid` logic, anchored there.
- **Checkpoint gates are editor-marked seams** — the author picks which
  joints count, up to **16 gates** (including start/finish). A seam is a port
  boundary, so a gate's span is simply the road cross-section there; no
  mid-segment anchoring. Validation requires at least start/finish plus one
  more gate (a lap must be earnable in order).

## Validity

A layout is **saveable** iff, walking the graph:

1. **Every port mated** — the fork-free ring closes back onto the origin
   pose (exact); with forks, every loose outlet lands exactly on an open
   inlet, and the **layer agrees at every mate** (returning to 0 at the
   start line).
2. **No same-layer overlap** — non-adjacent pieces on the same layer keep
   their footprints ≥ road-width apart (checked on deterministically sampled
   centerline points), with exactly two exceptions: a **crossable pair**
   (midpoints coincident, angle legal for their length) and **a road through
   a jump's gap**. Different layers may cross freely.
3. **One start** — exactly one start-grid piece (the ring is stored cut at
   its exit; grid room is guaranteed by the piece itself).
4. **Gates** — 2–16 marked seams, seam 0 always included; **every possible
   lap route crosses them in the same cyclic order** (routes enumerate at
   two per fork).
5. **Fits the canvas** — the whole footprint (road width included) stays
   inside the fixed canvas from the stored origin; and ≤ 64 pieces (also the
   encoding cap).

Anything else is an *editing* state, not an error — loose ends are simply
unsaveable, never a crash.

## Compile

`origin + [PieceID] + gate seams → Track`, directly — and this is now the only
track compiler, since the hand-authored `TrackDesign` path and its bundled JSON
were deleted once the built-ins became share codes:

1. Walk the graph from the **stored origin pose** with exact coordinates.
2. Emit the centerline: straights as segment endpoints, arcs sampled at the
   existing ≤ 6°/segment convention; lower to `Vec2` here.
3. Mark layer-1 stretches as `elevatedSegments`; emit `Ramp`s at ramp-piece
   seams (up = launches).
4. Emit `Gate`s at marked seams (cross-section of the road there), start
   slots via `startGrid`.
5. The track's `size` **is the fixed canvas** — the layout sits wherever the
   author put it, leaving deliberate room for decorations. ("Center on
   canvas" is an editor convenience that adjusts the origin, not a compile
   step.)

Compilation lands in the two phases from "Beyond the ring": **Phase A**
compiles rings + crossings + jumps onto today's single-centerline `Track`
(wall clipping at crossing mouths, no-flip launch); **Phase B** teaches
`Track` multiple routes and the AI a branch choice before fork pieces
compile. Built-ins migrate to this model **only if** the forcing-function
rebuild proves the catalog expressive enough — decided with the editor in
hand, per the roadmap.

## Primitives in the model, compounds in the code

**Built.** The catalog reduces to primitives — a short straight
and 45° corners at each radius — because everything else composes from them
*exactly* (measured: 2U = two shorts, long = four, 90° = two 45s, hairpin = four
45s, all with identical end poses). That reduction is worth having for reasons
that have nothing to do with bytes:

- **A checkpoint anywhere.** A hairpin built from four 45s has seams at the apex;
  as a single piece it has none, and a gate at the apex is what you usually want.
- **No variant holes.** No missing sweep hairpin, no jog-named-by-lateral-shift,
  and the "should a compound follow the selected radius?" question dissolves.
- **A far smaller palette.** 44 catalog entries become ~10, and the palette now
  offers *exactly* the primitive set: a left/right 45° pair on a radius carousel,
  the short straight, and the context-aware ramp. No 90° buttons and no one-off
  hotbar — a compound button was only ever taps saved, and it cost a palette that
  grew with the catalog plus a placement that took several presses to undo.

The cost is code length: the oval goes from 8 pieces to 15 primitives. So the
compounds move into the **encoding** as virtual elements — one id meaning "four
45° medium lefts" — which is strictly better than run-length encoding, because a
compound id *is* the run and costs one byte where RLE costs two (id + count).

Measured on the real built-ins, pieces section only:

| track | primitives (1 B each) | RLE | virtual compounds |
|---|---:|---:|---:|
| small | 16 B | 12 B | **7 B** |
| oval | 15 B | 9 B | **5 B** |
| eight | 21 B | 17 B | **11 B** |

Compounds roughly halve it; RLE manages 19–40%. Both are decoded to primitives
before anything else sees the layout, so the model stays uniform and there is
exactly one canonical byte form (the encoder always prefers the longest compound,
so a given piece list encodes one way — byte-stability is what makes a code an
identity).

**Decals are sparse `pos:decalId` pairs**, both varint, indexed against the
*expanded* primitive list so either half of a hairpin can be decorated
independently. A parallel array (one entry per piece) was rejected: for the oval
that is 15 B, three times the whole 5-byte piece section, even with nothing
decorated. Sparse wins until roughly half the track carries a decal.

**Seam indices become varint**, one byte up to 127. Today they are a single raw
byte, which silently truncates: a gate at seam 260 decodes as seam 4, verified.
That cannot happen at current track sizes but primitives make long tracks
ordinary. The 16-gate cap stays — it is a reasonable limit and cheap to raise
later, since gates are a length-prefixed section.

**Two separate caps, and they must not be confused.** Compounds make the encoded
count and the track length different numbers — a hairpin is one id but four
primitives — so:

- **Max encoded elements** bounds the *decode work*: how many ids a hostile code
  may contain before it is rejected. This is what today's `maxPieces = 64`
  actually checks.
- **Max length** bounds the *track*: primitives after expansion, and it must stay
  **under 128**, because a seam index addresses a primitive and a varint's first
  byte carries 7 bits.

Both are now enforced: `maxPieces = 64` on the encoded ids, and `maxLength = 127`
on the primitives, bounded **during** expansion (`PieceExpansion.expand(all:limit:)`
returns nil past the limit) rather than expanded-then-measured, so a small hostile
code cannot allocate a large layout.

For scale: real tracks are 15–21 primitives, and 127 shorts end to end is 15,240
units against a 5,866-unit canvas perimeter — roughly 2.6 laps of the outer edge.
Generous today; if the bigger-screen canvases land, re-measure rather than assume,
and revisit the QR budget honestly at the same time.

**"Close it" searches in compounds and returns primitives.** The search step stays
a compound — a hairpin is one step, not four — so a small depth budget can still
find a run that turns 180°; the winning run is expanded on the way out, since a
layout holds primitives. Same for the editor: one tap places a piece, and what
lands is whatever primitives it expands to.

**The ramp cap is a property of the elevated run, not of a piece.** Sealing the air
under a ramp's raised end used to be decided per piece, from whichever of its ends
sampled higher — so once a deck became two short straights, every deck piece
claimed a "high end" and dropped a cap across the middle of the bridge, blocking
the road underneath (a cap at 0.9 has floor `trunc(0.9)` = 0). Only a piece that
actually changes height owns a mouth to seal. The old one-piece deck hid this.

Still to do: the budget table below must be re-derived from measurements, since
every row changes.

## Encoding & the URL/QR budget

Share codes are **base64url** (no padding) of a small binary blob at
`https://skid.misaki.fi/t/<code>`. Geometry costs almost nothing — **the
code is the piece list plus one anchor pose** (the origin, so the layout
lands on the canvas exactly where its author placed it).

Layout *(v1)*:

```
byte 0      format version (1)
byte 1      CRC-8 of the rest (typo → "invalid code", not a garbage track)
then TLV sections, each: 1 byte tag · 1 byte length · payload
  tag 1  PIECES  payload = varint piece ids, in ring order  (required)
  tag 2  GATES   payload = one byte per gate seam idx       (required)
  tag 3  ORIGIN  payload = x:u16 · y:u16 · heading:u8       (required;
                 the start line's pose on the canvas)
  tag 4  THEME   payload = u8: 0 normal · 1 snow · 2 sand   (optional,
                 default normal — anticipated now, rendered later)
```

**Piece ids are varints**: ids 0–127 encode as one byte; a set high bit
means a two-byte id (`((b0 & 0x7F) << 8) | b1`, 15-bit space, ~32k ids).

**Allocation policy**: the scarce one-byte range is reserved for **core
geometry** (straights, curves, ramps, the start piece); **decals and other
variants live in the two-byte range from the start** — so the compact range
never needs a hard "which 128 matter most" call, and variant families can
multiply for years without a version bump. A decal piece costs one extra
byte in a code; a typical track carries a handful. The registry becomes
truly append-only **at the format's first public release** — until then,
reshuffling ids (breaking compatibility) is allowed while the editor takes
shape.

TLV keeps the format **expansion-proof**: future sections (hazards,
decorations, per-track width) are new tags that old decoders skip by length;
the version byte covers anything structural. Unknown piece ids in a *known*
version = "made with a newer Skid Jam".

**The running budget** (URL = 26 chars of `https://skid.misaki.fi/t/` + code;
QR byte capacities at M error correction):

| track | bytes | code chars | URL chars | QR fits in |
|---|---:|---:|---:|---|
| small (12 pieces, 4 gates) | 29 | 39 | 65 | V5 (84 B) |
| typical (20 pieces, 4 of them decals, 6 gates, themed) | 46 | 62 | 88 | V6 (106 B) |
| excessive (64 pieces, 8 decals, 16 gates, themed) | 104 | 139 | 165 | V9 (180 B) |
| future: excessive + ~60 B of decorations | ~164 | ~219 | ~245 | V11 (251 B) |

Even the worst case with a future decoration layer sits in a mid-size,
easily scannable QR. **Keep this table honest as sections are added** — the
goal is that *any* design fits a QR code; if a future section threatens
that, it must pack tighter (bitmask gates, 6-bit ids) before it ships.

### Why a custom binary format (and not JSON + deflate)

Considered and measured: minimal compact JSON for the typical track is
~125 B (~193-char URL); deflating it lands around ~95 B (~153 chars) because
**deflate can't amortize its overhead on payloads this small** — roughly
1.7–2× the binary TLV at every size, and the gap is exactly the headroom the
future decoration section needs. Two quieter reasons seal it:

- **Canonical bytes.** The TLV has one encoding per track, byte-identical
  everywhere — which matters the moment a code is used as an identity
  (dedup, per-track hiscores). JSON has key-order/whitespace ambiguity, and
  deflate output varies across library versions.
- **A ~100-line parser** with CRC-8 up front beats running untrusted input
  through a decompressor before validation; and nothing needs a human-readable
  form, since tracks are authored in the editor rather than typed out.

**Future headroom lever**, before any format surgery: QR *alphanumeric mode*
packs ~45% more characters per version than byte mode — a base32-uppercase
code (with an uppercased share path) would exploit it if the budget ever
tightens. Not needed at current sizes.

## A library of your own tracks *(planned)*

The custom slot in the setup picker is the first step; the shape it grows into:

- **A track's identity is a UUID, not its name.** Once designs arrive from
  other people by link/QR, two of them *will* be called "Hairpin" — so name
  can't be identity without forcing renames on import. A UUID also keeps
  hiscores stable across a rename (they key on `Track.id`).
- **Names are for humans and need not be unique.** Duplicates are the author's
  business; the UI can warn ("you already have a track called that") without
  blocking. Requiring uniqueness only creates dead ends.
- **Editing any track starts a copy.** Opening a built-in or an imported track
  in the editor copies it into your library with a fresh UUID and a default
  name ("Hairpin (copy)"), so the original is never mutated and there's no
  "pick a new name" gate before you can start.
- **The share code stays pure content.** It carries pieces, gates, origin and
  theme — deliberately no id, because the receiving device mints its own UUID
  on import. The *name* travels alongside as a new optional TLV section
  (tag 5 `NAME`), which the budget table already has room for.

**Signed tracks** *(wanted; sizing decided, not built)*. Each device holds an
Ed25519 keypair in the Keychain with `kSecAttrSynchronizable` so it follows
the user's iCloud, and a published track carries author + signature (tags 6
`AUTHOR`, 7 `SIG`). What that buys is **attribution**, not integrity against a
malicious sharer — anyone can strip a signature and re-sign as themselves,
because nothing vouches for which key is whom. Useful for "by *author*" and
for keying hiscores by (track, author); not an anti-cheat mechanism.

The catch is the **QR budget**: 32-byte key + 64-byte signature = 96 B, which
roughly triples a typical 46 B track and pushes the worst case past the V11
ceiling the format promises to stay inside. So signing is an **optional
section**, not mandatory: bare codes stay QR-sized, signatures ride along on
links (or on a truncated 32-byte signature, which is ample for attribution).
Keep the budget table honest when it lands.

## Open until wired up

- **The catalog pass implementing the unit system** — renumber every
  dimension (see "The unit system"), add S-chicanes, lane jogs, and the
  medium hairpin, verify the 2×2 start grid still fits the 240 start piece,
  and add the editor **gap readout** (report a loose end's offset to the
  closure target as U-axis + U-diagonal components).
- **The width pass** (after sizes; see "Road width — grip vs. visual"):
  per-port grip widths, outboard kerb band, per-edge kerb styling (red/white
  on curve outers vs. plain white on straights — renderer styling keyed off
  piece kind + side, a decal, not geometry).
- The **canvas constant** (ties to the ~1.2:1 taller-aspect convention;
  likely ~1600×1333) — fixed per format version once chosen.
- Gate-span shape at seams on tight curves (cross-section may need a nudge).
- Built-ins: migrate vs. stay free-form — after the rebuild experiment.
