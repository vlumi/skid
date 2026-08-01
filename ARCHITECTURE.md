# Architecture

What Skid Jam **is**, as built. Process and conventions live in
[AGENTS.md](AGENTS.md); *when* things happen is [ROADMAP.md](ROADMAP.md); *why*
a design was chosen is in the `docs/*-plan.md` files, linked from here.

Everything before "[Planned](#planned)" describes shipped code. That chapter is
fenced off deliberately: mixing the two is what let the previous architecture
notes drift into describing a model that had been replaced.

## The rule everything hangs on

**A control scheme is an input source, not a game mode.**

```swift
public protocol ControlSource {
    func input(for player: PlayerID, at tick: Tick) -> CarInput
}
```

`CarInput` is car-relative — steer and throttle, nothing screen-oriented. Touch
zones, on-screen sticks, AI, and (later) network peers are all just
`ControlSource`s. The sim never knows which. Local play, AI, and networked play
compose instead of each being a rewrite.

## Two targets, one seam

| | `SkidCore` | `SkidKit` |
|---|---|---|
| holds | physics, track model, race state, piece model | SwiftUI rendering, input capture, editor UI, persistence I/O |
| imports | Foundation, CryptoKit | SwiftUI, UIKit, CoreGraphics, AVFoundation, SkidCore |
| tested | headless, coverage-gated | coverage-ignored |

The rule: **testable logic goes in SkidCore.** Where a feature needs platform
I/O, the pattern is a versioned `Codable` model in SkidCore plus a dumb I/O
shim in SkidKit — `HiscoreBook`/`HiscoreFile` is the reference pair. The line is
worth defending: the control schemes are pure input math and sat in SkidKit,
outside the coverage gate, until four `CGRect` references were the only thing
holding them there.

CryptoKit is the one framework beyond Foundation in SkidCore: it is Apple's,
not a third-party dependency, and Ed25519 verification is a pure function of
bytes. Anything with I/O, entropy, or a UI stays out — key *generation* and
storage are SkidKit's.

Both targets and the tests group **by domain, not by type** —
`SkidKit/Editor/`, `SkidKit/Input/`, `SkidCore/TrackPieces/`,
`Tests/SkidCoreTests/Sim/`. A renderer that only the editor uses belongs with
the editor, not with the other renderers.

## The simulation

Deterministic by construction: same inputs → same state, bit-for-bit. This is
not a nice-to-have — replays, ghosts, and planned lockstep networking all stand
on it.

- `Race.advance(inputs: [PlayerID: CarInput])` at a fixed timestep.
  `tickRate = 60`, `dt = 1/60`.
- Physics is hand-written (position, velocity, heading, lateral slip, wall
  response). **Not** `SKPhysicsBody` — SpriteKit physics isn't guaranteed
  deterministic across devices.
- Randomness is injected and seeded (`SeededRNG`), never ambient.
- A replay is therefore just *seed + per-tick inputs* — tiny to store, which is
  what makes ghosts and hiscores cheap.

**Arcade drift.** Steering rotates the heading, throttle accelerates along it,
grip < 1 so lateral velocity carries the car wide. A drift *redirects* momentum
rather than scrubbing it — arcade, never manufacturing speed. Feel dials live
in `CarTuning` and are exposed in the pause-menu Tuning panel; physics dials
apply on reset, and hiscores only record on stock physics.

**Car contact is a race option** (`RaceConfig`), not a constant: contact cars
collide and bump, ghost cars pass through. Walls and surfaces behave the same
in both. Pairs resolve in index order, deterministically.

**AI is a `ControlSource`** — a pure function of car state + track, so it's
reproducible and lockstep-safe. It aims at a lookahead point along the
centerline, lifts for curvature, and backs out when pinned. No rubber-banding:
difficulty is a skill ladder over the driver's own dials, and AI cars are
mechanically identical to players'.

## The track model

A track is a **wide asphalt ribbon** with grass everywhere off it. Surfaces are
sim data, not decoration — `surface(at:)` is deterministic and the step applies
each surface's grip/drag. Asphalt is baseline; grass costs speed but is
survivable. Mud, water and oil are implemented in the sim (`Surface`) but no
track can carry them yet — they left with the old hand-authored tracks and come
back as placeable hazards.

**Height is a continuous value per centerline point** — 0 is ground, 1 is a
bridge deck, and a ramp varies across its length. This replaced an earlier
two-layer model (discrete `elevatedSegments` + a per-car integer layer), which
had to flip a car between layers at a line and produced a family of bugs that
couldn't be fully closed: popping on crossing, road vanishing mid-transition,
a car driving *under* a bridge surfacing on top of the ramp. With a height per
point, "which surface am I on" is a comparison, not a state machine. The ribbon
also widens with height — `halfWidth(atHeight:)` is what any "am I on the road"
question must use. See [docs/height-model-plan.md](docs/height-model-plan.md).

**Laps must be earned.** A track carries ordered directional gates; a lap counts
only when all are crossed in order before the finish. Gates are forgiving by
design — each spans the whole corridor, so cutting across grass still counts and
grass itself is the penalty. They exist to kill gross shortcuts only.

**At-grade crossings are implicit** — nothing declared or encoded. Two stretches
may share tarmac when both are at the same height *and* their lines meet at
≥ 45°. The height half is load-bearing: the angle test alone would permit a road
crossing a ramp, which is a solid embankment. See
[docs/crossing-plan.md](docs/crossing-plan.md).

## Tracks are built from pieces

Tracks are an ordered ring of catalog pieces, not hand-authored geometry — the
same data the editor manipulates, the sharing format, and the compiler input.
See [docs/track-pieces.md](docs/track-pieces.md).

```text
TrackLayout ──walk──> placed poses ──PieceCompiler.compile──> Track
   │                                                            │
   └── TrackCode.encode ──> share code                    what the sim races
```

**Exact geometry.** `Coord` is the value `(a + b·√2)/2` with integer `a`, `b` —
a ring closed under addition and under 45° rotation, so pieces walked at any of
the 8 headings land on exactly representable values. Loop closure is an integer
equality test, never a float tolerance. Operations that can't stay exact return
nil rather than rounding.

**One track, one spelling.** `normalized()` rotates a closed ring to its start
piece, so the same track built from different starting points encodes
identically. Reversal is deliberately *not* normalized away — the same road
driven the other way is a different track.

**Identity, not index.** `gateSeams`, `fitters`, `pitches` and `decals` are all
keyed by piece index, so every mutation remaps them together through the single
API in `TrackLayoutMutate` (`insert`/`remove`/`rotate`). Seam N is piece N's
exit; the finish line is the start piece's own seam.

**The validator** (`TrackValidator`) judges a layout independently of the
compiler: open ends, ribbon overlap, canvas bounds, gate rules, height closure,
unsolved fitters. Some problems block saving, others only block racing.

## The share code

A track travels as base64url of a small binary blob:

```text
byte 0    format version (1)
byte 1    CRC-8 over everything after it
then      TLV records — tag(1) · length(1) · payload
```

| Tag | Section | Written when |
|---:|---|---|
| 1 | pieces (varint ids) | always |
| 2 | gates (one byte per seam) | always |
| 3 | origin (x:u16, y:u16, heading:u8) | always |
| 4 | theme | non-default |
| 5 | base height (i8, half levels) | off ground |
| 6 | fitters (8 bytes each) | non-empty |
| 7 | decals (2 bytes each) | non-empty |

Nothing is positional — records carry their own tags, and encode writes them
`1,2,3,4,6,7,5`, out of numeric order. **Unknown tags are skipped by length**,
so a decoder tolerates sections it doesn't know. Optional sections are omitted
entirely when empty, so adding one costs zero bytes for tracks that don't use it.

Real tracks are **24–44 bytes** (32–59 code chars), comfortably inside a QR.

**One track, one code** — what lets a code serve as an identity for dedup and
per-track hiscores. `normalized()` handles the ring's rotation; `gateSeams` is
kept ascending by `TrackLayout` itself, because gate order carries no meaning
and letting it reach the bytes gave one track several codes.

A code carries **content only**. No id (the receiving device mints its own), and
no name.

## The editor

Phone-first, and the only way tracks are authored. Pieces are placed at a
selected **end** of the chain; a closed ring can be cut anywhere
(rotate-then-pop, so surviving road never moves). Selection is a piece, and
building is a property of a *selected end*.

Undo is a stack of encoded snapshots behind one hook (`recordingUndo`), so no
action can forget to record and a refused edit records nothing. Gating is its
own mode, which resolves the seam-tap vs piece-tap conflict outright.

Note `TrackCode.encode` runs on **every edit** for the undo snapshot — anything
added to that path is paid per keystroke.

## Couch multiplayer

2–4 players on one device, one thumb each. Each player owns a **zone** carrying
its own `up` vector, so a player seated across the table has their controls
rotated to face them and orientation is never ambiguous. A touch belongs to the
zone it started in for its whole life. Seating is a setup choice, never a guess.

Two schemes, swappable against the same sim: **Casual** (aim-to-drive — the
stick's angle is where you want to go) and **Pro** (direct steer/throttle
d-pad). Holding a drift by manual countersteer needs precision glass can't give,
which is why those two earned their place and the other candidates were cut.

Chrome respects the zones: HUD chips sit in each player's own corner, rotated;
meta actions never float over a thumb area.

---

## Planned

Not built. Nothing below describes existing code.

**Track signing** — Ed25519 attribution so a shared track carries its author.
Two new TLV sections at the top of the tag range (`pubkey = 254`, `sig = 255`),
keeping the low contiguous range for content. PUBKEY is a 32-byte raw public
key; SIG must be the last record, and the signature covers the body minus its
own record. Signing is a separate entry point from `encode`, so the per-keystroke
undo path stays free. The keypair lives in the Keychain, iCloud-synced. This buys
**attribution, not integrity** — anyone can strip a signature and re-sign as
themselves; nothing vouches for which key is whom.

**Track library** — many named tracks with UUID identity, replacing today's
single custom slot. Names stay local (a signed name couldn't be renamed), and
the receiving device mints identity on import. Import by link/QR follows;
clipboard works today.

**Jumps** — the catalog has the geometry and the editor has the buttons hidden;
the compiler can't build them yet.

**Forks and joins** — parked, and not for want of geometry (the pieces exist,
ids 34–36). Two reasons: the canvas is too small for branches that trade off
meaningfully, and route choice makes the track a graph rather than a ring, which
breaks every simplification built on that ring at once — `centerline` stops being
one array, `arcPosition` stops being a single number, and lap validity can't be
"collect every gate in order". A *join* alone (a branch merging back, carrying no
gates) keeps the lap on the trunk and is the cheap half.

**Local-network multiplayer** — deterministic lockstep over
MultipeerConnectivity, inputs-only sync, one peer as clock host. No server. The
sim has been built for this from the first line; that's why determinism is
non-negotiable above.

**Platforms** — macOS, keyboard and GameController as further `ControlSource`s,
landscape, iPad map-sizing.

Also planned, with detail in [ROADMAP.md](ROADMAP.md): placeable hazards and
scenery, track size classes, profiles and tournaments, and a real front end.

## Deliberately out of scope

No ads, no IAP, no accounts, no server, no global leaderboards, no third-party
runtime dependencies. Networked play is peer-to-peer on the local network only.
("No accounts" means no server/online accounts — local on-device player profiles
are fine.)

**No performance upgrades, ever.** Every car in a race is mechanically
identical; progression may only ever grant cosmetics. Upgrade trees are a
long-run balance burden, and the game is about skill — a newcomer must face the
same machine as the veteran.
