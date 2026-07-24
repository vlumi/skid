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

A **piece** occupies road between two **ports**. A port is a pose: position,
heading, and road width. Pieces carry their geometry in a local frame; placing
a piece means setting its entry port onto the current pose, and its exit port
becomes the next pose. A **track is an ordered list of piece ids** walked from
an origin pose — every joint mates by construction (there are no loose
intermediate ends to validate), and the ring **closes** when the walk's final
pose equals its starting pose exactly.

- **Headings quantize to 8 directions** (45° steps), stored as an integer
  0–7. Diagonals are first-class, not grid-cell approximations.
- **Width is one global constant in v1** (120 units — the shipped tracks use
  110–130), so all ports mate trivially. Per-track width can arrive later as
  an encoding section without changing the model.
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

### The editing model — one chain, geometry always derived

Editing works like laying rollercoaster track: the start line goes down
first, then the layout **extends piece by piece from the loose end**, in any
of the 8 directions the catalog allows, until the end pose meets the start
pose and the loop closes. The editor's state is the same ordered piece list
the share code carries — never a set of placed objects.

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

### Layers, ramps, bridges

Pieces don't carry an absolute layer. The walk tracks a **current layer**
(0 or 1): a *ramp-up* piece raises it, a *ramp-down* lowers it, and every
ordinary piece in between simply *is* elevated. Closure requires the layer to
return to 0. Same-layer overlap is invalid; **different-layer overlap is what
makes a bridge** — that's the whole Overpass trick, and it falls out of the
model for free.

## Catalog *(v1)*

One byte per piece id; the id space is an **append-only registry** — ids are
never renumbered or reused, so old share-codes keep decoding forever. New
pieces (and whole new families) are added by appending ids.

| id | piece | notes |
|---:|---|---|
| 0 | straight 150 | |
| 1 | straight 300 | |
| 2 | straight 600 | |
| 3–6 | curve 45° · L/R × radius 60/160 | tight and sweeper |
| 7–10 | curve 90° · L/R × radius 60/160 | convenience (= two 45s) |
| 11–12 | hairpin 180° · L/R, radius 60 | the Hairpin rebuild |
| 13 | ramp up (straight 300, layer +1, launches) | |
| 14 | ramp down (straight 300, layer −1) | |
| 15–17 | straight 150/300/600 **+ direction arrow** | decal variants |
| 18 | **start grid** (straight 300, grid decal, start line at exit) | exactly one per track |

Deliberately small — a phone-browsable palette — but designed to grow:
lengths/radii are plain integer parameters, so variants are new ids, not new
machinery. Expected later families: chicanes, S-bends, wider/narrower roads,
themed surface patches, more decals.

**Decals vs. decorations.** A *decal* is painted **on the road** and is part
of the piece — same geometry, different look — so it's simply another
catalog id (the direction-arrow straights above; later: painted kerb
variants, surface markings). A *decoration* lives **beside the road** (trees,
buildings, signs) with its own canvas placement, so decorations get their
own encoding section later, not catalog ids.

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

A layout is **saveable** iff, walking the ring:

1. **Closure** — final pose == origin pose (exact), and layer returns to 0.
2. **No same-layer overlap** — non-adjacent pieces on the same layer keep
   their footprints ≥ road-width apart (checked on deterministically sampled
   centerline points; different layers may cross freely).
3. **One start** — exactly one start-grid piece (the ring is stored cut at
   its exit; grid room is guaranteed by the piece itself).
4. **Gates** — 2–16 marked seams, seam 0 always included.
5. **Fits the canvas** — the whole footprint (road width included) stays
   inside the fixed canvas from the stored origin; and ≤ 64 pieces (also the
   encoding cap).

Anything else is an *editing* state, not an error — loose ends are simply
unsaveable, never a crash.

## Compile

`origin + [PieceID] + gate seams → Track`, directly (no `TrackDesign` detour
— the free-form path stays untouched alongside, per the earlier decision):

1. Walk the ring from the **stored origin pose** with exact coordinates.
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

Built-ins migrate to this model **only if** the forcing-function rebuild
proves the catalog expressive enough — decided with the editor in hand, per
the roadmap.

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
means a two-byte id (`((b0 & 0x7F) << 8) | b1`, 15-bit space, ~32k ids). The
whole v1 catalog — and a long way beyond — stays one byte per piece, but
decal and texture variants can multiply for years without a version bump.

TLV keeps the format **expansion-proof**: future sections (hazards,
decorations, per-track width) are new tags that old decoders skip by length;
the version byte covers anything structural. Unknown piece ids in a *known*
version = "made with a newer Skid Jam".

**The running budget** (URL = 26 chars of `https://skid.misaki.fi/t/` + code;
QR byte capacities at M error correction):

| track | bytes | code chars | URL chars | QR fits in |
|---|---:|---:|---:|---|
| small (12 pieces, 4 gates) | 29 | 39 | 65 | V5 (84 B) |
| typical (20 pieces, 6 gates, themed) | 42 | 56 | 82 | V5 (84 B) |
| excessive (64 pieces, 16 gates, themed) | 96 | 128 | 154 | V9 (180 B) |
| future: excessive + ~60 B of decorations | ~156 | ~208 | ~234 | V11 (251 B) |

Even the worst case with a future decoration layer sits in a mid-size,
easily scannable QR. **Keep this table honest as sections are added** — the
goal is that *any* design fits a QR code; if a future section threatens
that, it must pack tighter (bitmask gates, 6-bit ids) before it ships.

## Open until wired up

- The exact catalog numbers (lengths, radii, width) — tune on device once
  the editor renders them.
- The **canvas constant** (ties to the ~1.2:1 taller-aspect convention;
  likely ~1600×1333) — fixed per format version once chosen.
- Whether 90°/180° convenience pieces earn their ids or compose from 45s.
- Gate-span shape at seams on tight curves (cross-section may need a nudge).
- Built-ins: migrate vs. stay free-form — after the rebuild experiment.
