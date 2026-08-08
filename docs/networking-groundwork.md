# Networking: what to do before the spike

Three questions, answered against the code as it stands rather than from
memory. Nothing here is a commitment to build; it is what the spike will hit and
what can be de-risked cheaply first.

## What the sim already gives us

Better than expected, and it is worth being concrete about why:

- **`Race.advance(inputs: [PlayerID: CarInput])`** is already the exact shape
  lockstep needs: one tick, a pure function of that tick's inputs. There is no
  hidden clock, no wall-time, no per-frame randomness.
- **Fixed 60 Hz tick.** `Race.dt` is a constant; nothing reads elapsed time.
- **Seeded RNG** for the grid shuffle, proven stable across constructions.
- **`CarInput` is `Codable`** and tiny — two `Double`s and an optional third.
- **A determinism suite exists** and passes: identical runs produce identical
  states over 1800 ticks, plus per-feature determinism tests for the AI, aim
  drift, car contact and elevation.

So the usual lockstep retrofit — untangling variable timestep, removing
wall-clock reads, seeding randomness — **is already done**. That is what makes an
early spike cheap.

## Three things worth doing upfront

These are all small, useful on their own, and each removes a way the spike could
fail for an uninteresting reason.

### 1. Make `Race` hashable into a checksum *(the one that really matters)*

`Race` is `Equatable` but **not `Codable`** — `Car` and `CarState` are, the race
is not. A spike's core measurement is "did tick N produce the same state on both
peers", which needs a cheap, stable digest of the state.

Add a `stateHash` (FNV/CRC over the cars' positions, velocities, headings, and
progress) rather than encoding the whole race:

- it is the thing a divergence check compares, per tick, cheaply
- it makes **local** determinism tests sharper too: today
  `XCTAssertEqual(a, b)` says "these differ" without saying *when* they started
  to, and a per-tick hash gives the first diverging tick immediately
- it is useful before any networking exists, which is the point

**Do not** make `Race` `Codable` for this. The hash is a summary for comparison;
serialising the whole race invites someone to try to *send* it, which is the
opposite of inputs-only sync.

### 2. Quantise `CarInput` on the wire

`steer` and `throttle` are `Double`s in −1…1 and `aim` is radians. Three doubles
is 24 bytes per player per tick, and — worse — a `Double` is a needlessly exact
thing to agree on.

Quantise to **one byte per axis** (steer, throttle) and two for aim (~0.005 rad,
finer than a thumb). That is 4 bytes per player per tick, and it removes a whole
class of "the peers disagree in the last bit" problem, since both sides then step
the sim from *identical* quantised values rather than from two float paths.

Worth doing regardless of networking: it also shrinks stored ghosts, which are
already an input stream.

### 3. Write down the float-determinism assumption, and test it

**This is the real cross-device risk, and it deserves honesty rather than
optimism.** The sim uses `sin`, `cos`, `atan2`, `pow` and `sqrt` on the hot path
(`Race.applyAim`, `RaceWalls` glance/yaw, `Vec2(angle:)`). IEEE-754 pins `+ - * /`
and `sqrt` exactly; it does **not** pin transcendentals. Two different libm
implementations may differ in the last bit — and lockstep amplifies any
divergence without bound.

In practice:

- **arm64 iPhone ↔ arm64 iPad ↔ Apple-silicon Mac** all use the same Apple libm
  on the same architecture, so this is very likely fine
- **an Intel Mac** is the case that could genuinely differ
- a Swift or OS version difference across peers is a smaller but real version of
  the same risk

So: **add a cross-device determinism check to the spike itself** — run a fixed
input script on both peers and compare the per-tick hash from §1. If it holds on
the hardware that matters, the assumption is validated rather than assumed. If it
does not, the fallback is known and unglamorous: replace the transcendentals on
the sim path with table/polynomial versions the project owns, so every peer
computes bit-identical values by construction. That is a contained change —
roughly the ten call sites above — but it is worth knowing *before* building a
lobby on top.

## Which transport, and what "local network" means

The out-of-scope rules settle the frame: **peer-to-peer on the local network, no
server, no accounts.** Within that, the real options:

| | discovery | reach | notes |
|:--|:--|:--|:--|
| **MultipeerConnectivity** | automatic (Bonjour + **peer-to-peer Wi-Fi and Bluetooth**) | same LAN *and* no-LAN | Apple's couch-multiplayer answer; handles discovery, invitation and transport together |
| **Network.framework** + Bonjour | manual `NWBrowser`/`NWListener` | same LAN only | more control (UDP, custom framing), more code |
| **GameKit** real-time match | Game Center | internet | needs accounts — **out of scope** |

**MultipeerConnectivity is the right default**, and for a reason that answers the
question directly: it is *not* LAN-only. It uses infrastructure Wi-Fi when peers
share a network, and falls back to **peer-to-peer Wi-Fi / Bluetooth** when they
do not — so two phones on a train with no router still find each other. For a
couch game that matters more than throughput.

What it costs: an opaque transport (you get reliable and unreliable sends, not a
socket), a discovery UI you do not fully control, and a hard practical ceiling
around 8 peers. None of those bind us here — 4 players is the design target.

**Network.framework is the escape hatch**, worth naming so the spike does not
have to relitigate it: if MC's send latency or its reliability semantics turn out
wrong, the same inputs-only protocol runs over UDP with a hand-rolled Bonjour
browse. Keep the protocol independent of the transport for exactly that reason.

## Packet loss, and why lockstep makes it a latency problem

**Lockstep cannot skip a tick.** Every peer must have every player's input for
tick N before any of them can simulate tick N — so a lost packet does not cause
a glitch or a rubber-band, it causes a **stall**: every car freezes until the
input arrives or is resent.

That is the trade. A prediction/rollback design (what a fast-paced online shooter
uses) hides loss by guessing and correcting, at the cost of cars visibly snapping
when the guess was wrong. Lockstep never lies about the world; it just sometimes
waits. For four people on a couch looking at *one screen each but the same race*,
a brief universal freeze is far less confusing than four different opinions about
where the cars are.

What makes it survivable:

- **Inputs are tiny and idempotent**, so the cure is redundancy rather than
  retransmission: send tick N's input *together with the last few ticks*, and a
  single lost packet is repaired by the next one arriving ~16 ms later. This is
  the standard trick and it costs a handful of bytes.
- **An input delay buffer.** Run the sim a fixed 2–4 ticks behind the newest
  input, so a late packet has time to arrive before its tick is needed. That
  converts loss into *constant* input latency (~33–66 ms) instead of visible
  stalls — the single most important tuning knob, and the one the spike should
  measure against feel.
- **Reliable sends for anything that is not per-tick input** (join, track
  selection, race start), where ordering matters more than latency.

So the honest summary: **loss shows up as input lag, not as teleporting cars**,
provided inputs are sent redundantly and the sim runs slightly behind. If loss is
sustained rather than occasional, it degrades to everyone waiting — which is the
correct failure mode for a shared race, and one the spike should deliberately
provoke (drop a peer mid-race, and see what the other screens do).

## What the spike still has to answer

Even with all of the above:

- does inputs-only sync hold **bit-identically across two real devices**
- what input delay still **feels** like driving (a feel question, not a
  measurement — it goes on device)
- what a **dropped peer** does to the other screens
- what a **late joiner** sees (probably: cannot join a race in progress, only
  the next one — worth confirming rather than assuming)
