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

**Total players: 8, and that ceiling is geometric rather than arbitrary.** The
start grid lives on the start piece, which is 2U = 240 units long, and slots run
back from the line at `back 70 + (n−1) × gap 50`:

| slots | grid depth | fits the 2U start piece? |
|--:|--:|:--|
| 4 | 220 | **yes** (20 units spare) |
| 6 | 320 | no |
| 8 | 420 | no |

So **4 is what the current grid holds** (`PieceCompiler.Grid.slots`), and going
beyond it needs a decision, not just a bigger number: a longer start piece, a
tighter `gap`, or staggering more than two abreast. The **palette is also 8
colours**, and per [first-glance-plan.md](first-glance-plan.md) the eight are not
all comfortably distinguishable — so 8 is the honest ceiling for "you can tell
whose car is whose", which is the point of a party game.

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

**What "raise the cap" actually means**, if 8 ever feels tight: a longer start
piece (the grid is the binding constraint), more palette colours that survive the
ΔE test, and a `CouchRig` that can lay out more than four bands. None of those are
network work — which is the useful part: the transport can carry 8 from day one
regardless.

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
