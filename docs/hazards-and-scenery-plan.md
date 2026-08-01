# Hazards and scenery: plan

> **Not started.** Design for the two remaining v0.6 content items — hazards as
> placeable pieces, and the catalog beyond road pieces. What the model does
> *now* is [ARCHITECTURE.md](../ARCHITECTURE.md).

The roadmap bundles "catalog beyond road pieces" into one item, but it is three
problems with different costs. Splitting them is most of the design.

| Tier | What | Placement | Encoding cost |
|---|---|---|---|
| 1 | More road pieces | Ports, as today | Free — one varint id |
| 2 | On-ribbon paint | Piece index | ~2 B per decorated piece |
| 3 | Hazards, scenery | Free position | ~6 B per item, **new section** |

Only tier 3 needs anything the format has never carried.

## Tier 1 — more road pieces

New catalog ids; placement and encoding already work. The gaps the unit system
already names (see [track-pieces.md](track-pieces.md) "The unit system"):

- **S-chicane at sweep radius** — tight and medium exist, sweep does not.
- **The medium hairpin** — listed as settled, never added.
- **The 120 lane jog** (medium↔tight), which that doc calls "the one hole".

Ids 42+ are free in the one-byte varint range. Nothing else to decide.

## Tier 2 — on-ribbon paint

The decal precedent, widened: more arrow colours, start-line variants, per-edge
kerb styling, surface texture on grass and mud. Keyed by piece index, in a
section omitted when empty.

The roadmap folds the **ramp-wall vs deck-rail distinction** in here, but that
one is not decoration — the sim already knows which is which
(`PieceCompiler.deckRails` vs the ramp embankment). It is a pure rendering fix
with no encoding at all, and can ship independently.

## Tier 3 — hazards first, scenery later

**Hazards are gameplay, scenery is polish**, so hazards go first and what they
teach shapes the decorative one.

### Most of the sim already exists

Worth stating plainly, because it makes this much smaller than the roadmap
implies:

- `Surface` already has `.water`, `.mud`, `.oil`, with grip and drag tuned.
- `SurfacePatch` already exists — centre, radius, surface, **height**.
- `Track.surface(at:height:)` already consults patches, and already gets the
  height right so oil on a deck does not affect the road underneath.

What is missing is **encoding, editor placement, and rendering**. The
deterministic path is done.

### Free position, not anchored

Hazards need their own coordinates rather than a piece index and offset:

- An oil slick's whole point is sitting at a chosen spot on the racing line.
- A puddle straddles the road edge — half on the ribbon, half off.
- Mud in the run-off has no piece it belongs to.

Anchoring would fight all three. Scenery is genuinely mixed (a grandstand is
trackside, a building is not), which is why its mechanism stays open — by then
the editor will have been used, and the answer will be observable rather than
guessed.

### Encoding

```text
tag 8  HAZARDS   6 bytes each:
       kind:u8 · x:u16 · y:u16 · size:u8
```

Positions are plain quantized integers, not `Coord`: a hazard closes no loop, so
it needs no exact arithmetic. Height is derived from the road beneath it rather
than stored — a hazard sits on whatever it is placed on, and storing it
separately invites the two disagreeing.

**Rotation is deliberately deferred.** The roadmap wants "rotatable, combinable
blobs", and combining buys shape more cheaply: two overlapping circles read as a
puddle for the same 6 bytes. If rotation still feels missing after device use,
it is one more byte.

**Cap at 16**, like gates. Four hazards ≈ 26 B, so a typical track goes 44 → 70 B
— comfortably QR-sized. Twenty would be 126 B, which is where the budget starts
to hurt.

### Steps

1. **`HAZARDS` section** — encode/decode, the cap, and the hostile-input tests.
   `SurfacePatch` already carries the runtime shape, so the compiler just emits
   patches from the section.
2. **Editor placement** — a hazard mode, like gate mode: tap to place, drag to
   size, tap to remove. Reuses the mutation/undo API unchanged, since hazards
   are not piece-indexed and so need no remapping.
3. **Rendering** — patches drawn under the cars, on the ground layer only.
4. **Scenery**, once hazards have been used: reuse the free-position section if
   that reads well in the editor, or add a cheaper anchored one if most scenery
   turns out to be trackside dressing.

## What this does not decide

- **Rotation and combination** for hazard shapes — revisit after device use.
- **Scenery's placement mechanism** — deliberately open, see above.
- **Surface textures** for grass and mud (tier 2, no encoding).
- Whether a hazard can sit on a **deck**. The model allows it (patches are
  height-aware); whether the editor should offer it is a UI question.
