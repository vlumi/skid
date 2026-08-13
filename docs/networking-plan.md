# Networked play — the steps

> **Superseded in part.** Steps 1–3.5 were built and Step 4 (the spike) ran on
> two phones — and answered its question with a measured *no for this product*:
> lockstep's stall-rather-than-lie is the wrong trade on a bursty transport, and
> it worsens with every device added. The runtime now uses **host-authoritative
> snapshots** — see [networking-model-analysis.md](networking-model-analysis.md)
> for the decision and [networking-spike-log.md](networking-spike-log.md) for
> what the spike found. The groundwork below (wire format, roster, lobby,
> transport, determinism) carries over; the lockstep-specific steps do not.

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
(§Step 1) is exactly the thing that will later say whether an Apple-silicon Mac
can join. **Intel Macs are out of scope** — there is none available to test on,
and an untestable platform is not a supported one.

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
- **The color palette is global too**, so seat 3 is the same color on both
  screens — which the first-glance work (see
  [first-glance-plan.md](first-glance-plan.md)) makes more visible, not less.

### How many devices, and how many players total? — **9 players, 4 per device**

Worth fixing upfront, because a protocol needs a maximum and retrofitting one is
worse than choosing it.

**9, and both the grid and the palette reach it comfortably.**

*The grid is not the constraint* — an earlier version of this doc said it was, on
the arithmetic of keeping the current 2-abreast staggering and only adding rows.
Wrong question. The two cars sit at ±28 with **36 units of air between them** and
22 spare to each kerb, so the grid is wasting its width, not running out of length.

Measured against the real geometry (2U = 240-unit start piece, 120-wide road,
34 × 20 car with a 12 collision radius):

| row width | center pitch | clearance between cars |
|--:|--:|--:|
| 2 abreast | 88 | 68 |
| **3 abreast** | **44** | **24** — more than a car's collision diameter |
| 4 abreast | 29 | 9 — under the collision radius, cars start touching |

So **3 is the widest usable row**, and 3 × 3 = 9 slots needs only **170 of the 240
units** at the existing `gap` of 50. Nothing about the start piece changes.

*Nor is the palette* — nine distinguishable colors are easy once the hue circle
is used properly rather than reaching for `.pink` and `.white`:

```
red · orange · yellow · green · teal · cyan · blue · purple · magenta
```

Worst pair **ΔE 32.8** (blue vs purple), against the current palette's **21.0**
(red vs pink). So nine colors are *more* distinguishable than today's eight — the
cap rises and legibility improves at the same time. Keep the minimum-ΔE test from
[first-glance-plan.md](first-glance-plan.md) as the guard.

**Per device: up to 4**, which is what a `CouchRig` lays out (four control bands
around one map) and what fits a phone. Nothing in the protocol should assume it — a
device announces how many seats it brings. That implies **up to 9 devices**, still
inside MultipeerConnectivity's practical ceiling.

Both caps are policy and belong in one named place in `SkidCore`, not scattered as
literal `4`s (`CouchGame`'s `min(4, count)` and `4 - playerCount`, plus
`Grid.slots`).

### How the grid fills, per player count

One rule does the work, and it is the one real grids obey: **a row is never wider
than the row ahead of it**, and the short row goes at the **back**. Front rows fill
first, so the cars ahead of you are never fewer than the cars beside you.

That leaves one genuine choice: **2 abreast is much roomier per car** (68 units of
air vs 24), so it is worth keeping while the count is small enough to fit in two
rows.

| cars | rows | why |
|--:|:--|:--|
| 1 | 1 | |
| 2 | 2 | |
| 3 | 2:1 | |
| 4 | **2:2** | keeps the roomy pairs; **3:1** would strand one car alone behind three |
| 5 | 3:2 | 3 abreast starts here — 2:2:1 would be three rows for five cars |
| 6 | **3:3** | not 2:2:2 — same reason: two rows beat three, and 3:3 is symmetric |
| 7 | 3:3:1 | |
| 8 | 3:3:2 | |
| 9 | 3:3:3 | |

On the specific questions asked:

- **5 as 3:2, not 2:2:1.** Both are legal, but 2:2:1 spends three rows on five
  cars and puts the last one alone two rows back — a worse start for that player
  and a longer grid for no gain.
- **6 as 3:3, not 2:2:2.** Symmetric either way, but 3:3 is two rows instead of
  three, so the field is tighter at the flag and the back row is not 100 units
  behind the front.
- **4 as 2:2** is the one place *not* to front-load. Pure front-loading gives 3:1,
  which is monotonic and legal but wastes the width advantage of pairs and isolates
  the fourth car. 4 players is also the most common couch case, so it is the one
  worth tuning by hand.

The rule in one line: **2-abreast while the field fits in two rows (≤ 4), then
3-abreast, front-loaded.** Everything above falls out of that, and it needs no
per-count table in the code.

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

### Step 1 — Determinism you can point at *(no networking)* — **done**

- **A per-tick state hash on `Race`** (`Race.stateHash`, FNV-1a over the whole
  car state). `Race` is `Equatable` but not `Codable`, and it stays that way — a
  summary invites comparison, a serialised race invites *sending* it, which is
  the opposite of inputs-only.
- **The existing determinism test now reports the tick.** Sabotaged with unseeded
  randomness at tick 900, it prints `runs diverged at tick 900 of 1800` ahead of
  the 30 KB state dump that previously said only "these differ".
- **`RaceRecording.replayHashes(on:)`** — the sequence a divergence check
  compares, and the same call a networked peer will use. A replayed recording
  matches a live run tick for tick.
- **The golden-hash tripwire landed early** (it was Step 3's), since it cost
  nothing once the hash existed: a fixed script's sampled hashes are pinned as
  literals, so a new Xcode, a different libm or another architecture turns the
  build red instead of silently disagreeing on device.

Two things learned in the building, both worth keeping in mind:

- **The hash covers the whole car state, not a chosen subset.** `steerActuator`
  reads like a rendering detail and is carried state; a partial digest would
  *earn* trust it does not have.
- **`CarState.wallContact` is excluded**, verified rather than assumed: every
  read of it is `RaceWalls` reading back its own accumulator, and none of it
  reaches position, velocity or heading. Hashing an output risks peers halting
  over a haptics counter; missing real state hides the failure. When a new field
  is ambiguous, hash it.

### Step 2 — A wire format for inputs *(no networking)* — **done**

- **`CarInputWire`**: one byte each for steer and throttle, two for aim. 24 bytes
  → 4 per player per tick, and both peers then step from *identical* quantised
  values rather than two float paths.
- **`CarInput.quantised` is the rule that makes it work.** Apply it to local input
  too, not only to what arrives off the wire. A peer that sends quantised input
  while stepping its own raw thumb value has two different races and diverges
  slowly, invisibly, and for a reason that looks like a physics bug. A test asserts
  that a quantised race *differs* from a raw one, so the asymmetry cannot be
  mistaken for harmless.
- **A quantised race stays deterministic**, hash sequence stable, verified against
  Step 1's hash.

Two things found in the building:

- **NaN and infinity trapped.** `max(-1, min(1, nan))` is `nan` in Swift, so the
  ordinary clamp does not catch it and `Int8(nan.rounded())` crashes — a malformed
  packet from a peer would have taken the app down rather than driving badly.
  Guarded on `isFinite`, with the crash reproduced by sabotage first.
- **Ghosts do *not* shrink for free**, as this doc previously claimed.
  `RaceRecording` is persisted inside `Hiscores`, so changing its stored format
  invalidates every existing ghost. Real saving, but it is a migration and belongs
  with other hiscore-file work.

`aim` needed no range agreement: the sim consumes it only as
`atan2(sin(aim - heading), cos(aim - heading))`, so it is a direction on a circle
and π/−π are one command. 65 535 steps over a full turn is 0.0055°, some three
orders finer than a thumb on glass.

### Step 3 — The float-determinism question, answered *(no networking)*

The real cross-device risk, and worth settling before building a lobby on it. The
sim calls `sin`/`cos`/`atan2`/`pow` on its hot path (~10 sites), and IEEE-754 pins
arithmetic and `sqrt` but **not** transcendentals.

- **A golden-hash test** — **done in Step 1**: a fixed input script's sampled
  hash sequence, pinned as literals. It passes trivially on the dev machine and
  is a tripwire the moment CI, a new Xcode, or another architecture disagrees.
  **If it ever fails, do not re-pin the number** before finding out what changed
  — a physics change legitimately needs re-pinning, a *platform* difference is
  the thing lockstep cannot survive, and re-pinning hides it.
- What remains for Step 4: ship that hash to a second device and compare. If it
  holds on Apple silicon, the assumption is *validated* rather than assumed.
- **If it ever fails**, the fallback is known and contained: own the
  transcendentals on the sim path so every peer computes bit-identical values by
  construction. Not doing that speculatively — and now much less likely to be
  needed at all, since dropping Intel leaves every supported peer on arm64 with
  Apple's own libm. Hand-rolling `sin`/`cos`/`atan2`/`pow` across ~10 hot-path
  sites would cost accuracy and speed to solve a problem no supported
  configuration has.

### Step 3.5 — The lockstep clock, transport-free *(no networking)* — **done**

Everything about lockstep that can be wrong in an interesting way turned out to be
testable in one process, so it was built before touching MultipeerConnectivity.
That leaves the spike itself to answer only what genuinely needs two devices.

- **`LockstepClock`** — decides *when* a tick may run: every seat's input in hand,
  plus the delay buffer's slack. Returns `nil` rather than an empty input set when
  a tick is not ready, because **substituting a coast for a late input is the one
  shortcut that silently forks the race** (the peer that received it simulates
  something else). A test asserts the absence of that convenience.
- **`Stall`** names its cause — `waitingForInput(tick:missing:)` or
  `buffering(tick:ticksBehind:)`. A stall with a named cause is a measurement; a
  frozen screen is a bug report.
- **Redundancy works and its limit is pinned.** `Packet.history` is 3, so two
  consecutive losses are repaired by the next packet and the third stalls. Both
  halves are asserted — the limit is the useful part of the claim.
- **First value wins on a redundant copy.** If a later copy could overwrite an
  earlier one, two peers receiving the copies in different orders would diverge —
  a desync caused by the repair mechanism itself.
- **`DivergenceWatch`** — trades `stateHash` per tick and reports the first
  disagreement, by tick and by peer. `agreement(at:)` returns `nil` rather than
  `true` when nobody has reported: "nobody disagreed" and "everybody agreed" are
  different claims, and conflating them lets a silent peer read as a healthy one.
  Earliest tick wins even when reported late, since reports arrive out of order.

**`Codable` is not a wire format — measured.** A packet of two seats × three ticks
is 28 bytes of payload and **438 bytes of JSON**, because every seat id is spelled
out as a dictionary key on every tick: 26 KB/s per peer at 60 Hz for data that fits
in 1.7. So `Packet.encoded(roster:)` names the seats *once*, positionally against
the roster both peers agreed at join time. A nine-seat field with full redundancy is
**113 bytes**.

That change surfaced a genuine hazard: **a 24-byte payload divides evenly by a
3-seat roster as well as a 2-seat one**, so a roster mismatch decoded cleanly and
invented inputs for a seat that never sent any. Length alone cannot catch it, so the
packet states its own seat count.

### Step 4 — The spike: two phones, one race

The smallest thing that answers the question. No lobby, no menus, no join flow —
hardcode if it helps.

- **MultipeerConnectivity**, one peer as clock host. Chosen because it is *not*
  LAN-only (falls back to peer-to-peer Wi-Fi/Bluetooth), which suits a couch.
- **Exchange the golden hash first**, before any race: same track, same seed,
  same build → same hash, or stop and find out why.
- **Then per-tick inputs** via `LockstepClock.Packet` — redundancy, gating and
  parsing already built and tested (§Step 3.5), so the spike supplies only the
  transport.
- **Compare per-tick hashes live** with `DivergenceWatch` and log the first
  divergence. A divergence is the point of the spike, not a setback.
- **Provoke the bad cases deliberately**: kill a peer mid-race, background one,
  walk out of Wi-Fi range.
- **Write the verdict down** either way, with the measurements.

The knob to tune here is **how far behind the newest input the sim runs** —
`LockstepClock.delayTicks`, already wired and defaulting to 2. That converts packet
loss into constant input lag instead of stalls, and what it costs in *feel* is a
device question, not a measurement. It is the one parameter here that no test can
settle.

**What the spike still has to supply**, now that the logic is done: the
MultipeerConnectivity session and its local-network privacy strings, wiring
`LockstepClock` into `GameSession.advance(to:)` in place of the bare accumulator
condition, and a seat roster agreed at join time (global numbering, per §"One player
per device").

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
2. **Float divergence across devices.** Was second on this list; now much
   smaller. Intel is out of scope (nothing to test on), so every supported peer
   is arm64 running Apple's libm — leaving only the iOS-vs-macOS libm difference
   on identical silicon, which the golden hash catches if it ever bites. What is
   left of this risk the spike measures for free, by trading hashes.
3. **MC's transport behavior** — send latency or reliability semantics that do
   not suit 60 Hz. The escape hatch is UDP via Network.framework, which is why
   the protocol must not name its transport.
4. **The sim drifting out of lockstep shape** as features land. A gap or a warp
   is fine (pure geometry), but anything reading wall time, device state or
   unseeded randomness breaks it silently. The golden-hash test is the guard.
