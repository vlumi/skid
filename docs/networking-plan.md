# Networked play — the steps

Groundwork, transport choice and the packet-loss analysis are in
[networking-groundwork.md](networking-groundwork.md). This is the build order,
and the three scope decisions that shape it.

## The scope questions, answered

### iOS only first? — **Yes, two iPhones.**

The spike's job is to answer "does inputs-only sync hold over a real network".
Adding a Mac to that adds a second variable — a different libm, a different input
scheme, a different window size — to an experiment whose whole point is isolating
one unknown. Two iPhones share an architecture and an OS, so a divergence there
is a *protocol* bug rather than a platform question.

**But structure it so the Mac is a later step, not a rewrite**: nothing in the
protocol should mention a device kind, and the cross-device determinism check
(§Step 1) is exactly the thing that will later say whether an Intel Mac can join
at all.

Second reason to start on iOS: two phones is the configuration a couch actually
has.

### One player per device? — **No, and the code already agrees.**

`CouchRig` maps *N seats to one screen* today, and `PlayerID` is just an index —
so "one player per device" was never baked in. Keeping that flexibility is nearly
free and is what makes the feature interesting: **two phones with two players
each is a four-player race**, which is a better party than four phones.

The model that falls out:

- a **device owns a set of seats** (1–4, whatever its rig is configured for)
- the network carries **inputs keyed by `PlayerID`**, which is already what
  `advance(inputs:)` takes
- every peer simulates **every** car, as it does now

So a device is not a player. It is a **screen with some players sitting at it**.

Two consequences worth deciding early:

- **Seat numbering must be global**, not per-device. Two phones each thinking
  they own seats 0–1 is the first bug this design would hit. The host assigns
  seat ranges at join time.
- **The colour palette is global too**, so seat 3 is the same colour on both
  screens — which the first-glance work (see
  [first-glance-plan.md](first-glance-plan.md)) makes more visible, not less.

### How many devices, and how many players total? — **8 players, 4 per device**

Worth fixing upfront, because a protocol needs a maximum and retrofitting one is
worse than choosing it.

**Total players: 8, and the grid is NOT the constraint** — an earlier version of
this doc claimed it was, on the arithmetic of keeping the current 2-abreast
staggering and simply adding rows. Wrong question: the grid is generously spaced
and packs far more without lengthening the start piece.

Measured against the real geometry — the 2U (240-unit) start piece, a 120-wide
road, a 34 × 20 car with a 12 collision radius:

| layout | cars | depth used | side clearance |
|:--|--:|--:|--:|
| current: 2 abreast × 4 | 8 | 220 / 240 | 36 between the pair |
| **3 abreast × 3** | **9** | 170 / 240 | 24 |
| 3 abreast × 4 | 12 | 220 / 240 | 24 |
| 4 abreast × 4 | 16 | 220 / 240 | 9 — too tight |

The current grid wastes its width: the two cars sit at ±28 with **36 units of air
between them** and 22 units spare to each kerb. Three abreast across a ±44 span
still leaves **24 units between cars** — more than a car's own collision diameter
— and the outermost edge lands at 54 of the 60 half-width.

So **3 abreast × 3 rows = 9 slots covers an 8-player cap with a row to spare**,
using less of the start piece than the grid does today. Nothing about the start
piece has to change.

Which makes the real ceiling the **palette**: 8 colours, and per
[first-glance-plan.md](first-glance-plan.md) not all 8 are comfortably
distinguishable (red vs pink is ΔE 21 today). "You can tell whose car is whose" is
the point of a party game, so **8 is an honest cap for colour reasons, not
geometric ones** — and raising it means finding more distinguishable colours, not
more tarmac.

4 abreast is where geometry does bite: 9 units of side clearance is less than a
car's collision radius, so cars would start the race already touching. Not worth
it for a cap the palette already limits.

**Per device: up to 4**, which is what a `CouchRig` already lays out (four control
bands around one map) and what fits a phone screen. Nothing in the protocol should
assume it — a device announces how many seats it brings.

So the shape to design for:

- **max 8 players total** — pick the number the protocol reserves bits for, and
  the number the lobby refuses to exceed
- **max 4 per device**, because that is a screen-layout limit, not a network one
- **max 8 devices**, trivially implied (8 devices × 1 seat), and comfortably under
  MultipeerConnectivity's practical ~8-peer ceiling

Both limits are *policy*, and they belong in one place in `SkidCore` rather than
scattered as `4`s — today the cap appears as literal `4`s in `CouchGame`
(`min(4, count)`, `4 - playerCount`) and as `Grid.slots`. Naming them is a
prerequisite for raising either, and it is a cheap first step.

**What "raise the cap" actually means**, if 8 ever feels tight: **more
distinguishable colours** first (the actual ceiling), and a `CouchRig` that lays
out more than four bands per screen. The grid itself has room — 3 abreast × 4 rows
is 12 slots inside the existing start piece. None of that is network work, which
is the useful part: the transport can carry 8 from day one regardless.

## Where the network plugs in

Two lines of `GameSession.advance(to:)`, and nothing else:

```swift
while accumulator >= Race.dt, ticks < Self.maxTicksPerFrame {   // ← WHEN a tick may run
    var inputs: [PlayerID: CarInput] = [:]
    for player in players {
        inputs[player] = inputFor(player, race)                 // ← WHERE inputs come from
    }
    recording.append(inputs)
    race.advance(inputs: inputs)
```

- `inputFor` is **already an injected closure** (`(PlayerID, Race) -> CarInput`),
  used today for local controls, the AI and ghost playback. A networked source is
  one more implementation.
- the `accumulator` loop is the only thing that decides a tick may run. Lockstep
  replaces that condition with "…and every peer's input for this tick has
  arrived".

And `RaceRecording` is already `seed + players + per-tick inputs` — which is the
wire protocol with the network removed. That is not a coincidence; it is the
same idea, and it means the protocol has a working reference implementation and a
test corpus before any socket exists.

## The steps

Each step is independently useful and independently mergeable. The first three
have no networking in them at all.

### Step 1 — Determinism you can point at *(no networking)*

- **A per-tick state hash on `Race`.** `Race` is `Equatable` but not `Codable`;
  a digest over cars' position/velocity/heading/progress is what a divergence
  check compares. Deliberately **not** making `Race` Codable — a summary invites
  comparison, a serialised race invites *sending* it, which is the opposite of
  inputs-only.
- **Sharpen the existing determinism tests with it.** Today
  `XCTAssertEqual(a, b)` says two 1800-tick runs differ without saying *when*.
  Per-tick hashes give the first diverging tick, which is the difference between a
  five-minute and a five-hour debug session.
- **A replay-from-recording check**: feed a `RaceRecording` back through a fresh
  `Race` and assert the hash sequence matches. This is lockstep, single-process —
  if it fails, nothing downstream can work.

### Step 2 — A wire format for inputs *(no networking)*

- **Quantise `CarInput`**: one byte each for steer and throttle, two for aim.
  24 bytes → 4 per player per tick, and both peers then step from *identical*
  quantised values rather than two float paths.
- **Round-trip tests**, and one that matters more: a race driven by quantised
  inputs must still be deterministic, and its hash sequence stable.
- Free side-effect: **ghosts get smaller**, since they are already input streams.

### Step 3 — The float-determinism question, answered *(no networking)*

The real cross-device risk, and worth settling before building a lobby on it. The
sim calls `sin`/`cos`/`atan2`/`pow` on its hot path (~10 sites), and IEEE-754 pins
arithmetic and `sqrt` but **not** transcendentals.

- **A golden-hash test**: a fixed input script's hash sequence, pinned as a
  literal in the test. It passes trivially on the dev machine and becomes a
  tripwire the moment CI, a new Xcode, or another architecture disagrees.
- Ship that hash to a second device in Step 4 and compare. If it holds on Apple
  silicon, the assumption is *validated* rather than assumed.
- **If it ever fails**, the fallback is known and contained: own the
  transcendentals on the sim path so every peer computes bit-identical values by
  construction. Not doing that speculatively.

### Step 4 — The spike: two phones, one race

The smallest thing that answers the question. No lobby, no menus, no join flow —
hardcode if it helps.

- **MultipeerConnectivity**, one peer as clock host. Chosen because it is *not*
  LAN-only (falls back to peer-to-peer Wi-Fi/Bluetooth), which suits a couch.
- **Exchange the golden hash first**, before any race: same track, same seed,
  same build → same hash, or stop and find out why.
- **Then per-tick inputs**, with each packet carrying the last few ticks
  redundantly — loss is repaired by the next packet ~16 ms later.
- **Compare per-tick hashes live** and log the first divergence. A divergence is
  the point of the spike, not a setback.
- **Provoke the bad cases deliberately**: kill a peer mid-race, background one,
  walk out of Wi-Fi range.
- **Write the verdict down** either way, with the measurements.

The knob to tune here is **how far behind the newest input the sim runs** (2–4
ticks). That converts packet loss into constant input lag instead of stalls, and
what it costs in *feel* is a device question, not a measurement.

### Step 5 — The product, only if Step 4 says yes

- Host/join UI, seat assignment (global numbering), track agreement, a ready gate
- Reconnect, or an honest failure: a peer that drops mid-race probably cannot
  rejoin *that* race — worth confirming rather than assuming
- **Pause semantics**, already flagged as an open question: whose tap freezes
  everyone? Likely host-only or no pause in a networked race
- Local-network privacy strings and Bonjour service declarations
- Then, separately: **Mac and iPad as peers**, which is where the Step 3 work
  earns its keep

## What could still kill it

Honest list, in rough order of likelihood:

1. **Input lag that ruins the feel.** The drift model is twitchy — that is the
   point of it — and 50 ms may be more noticeable here than in a slower game.
   This is a feel question and the spike must answer it on device.
2. **Float divergence across devices.** Unlikely within Apple silicon, real
   across architectures. Step 3 makes it visible rather than mysterious.
3. **MC's transport behaviour** — send latency or reliability semantics that do
   not suit 60 Hz. The escape hatch is UDP via Network.framework, which is why
   the protocol must not name its transport.
4. **The sim drifting out of lockstep shape** as features land. A gap or a warp
   is fine (pure geometry), but anything reading wall time, device state or
   unseeded randomness breaks it silently. The golden-hash test is the guard.
