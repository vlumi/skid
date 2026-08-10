# The networking model, analyzed fresh

> **Decision taken.** Option C was built: `RaceSnapshot` (the codec),
> `HostRelay`/`ClientView` (the sync), the `snapshotClient` seam in
> `GameSession`, and the lockstep runtime path deleted. The lockstep patch of
> §"A residual bug" was skipped deliberately — the scaling argument settled the
> direction, so its only remaining value (diagnosis) could not change the
> decision. This document stays as the reasoning of record.

Written after the spike (see [networking-spike-log.md](networking-spike-log.md))
with the question: patch lockstep, restructure it, or change the model. The
answer proposed here: **fix one residual transport bug regardless, then switch
the model to host-authoritative snapshots.** The reasoning follows.

## What the current model is

Deterministic peer-to-peer lockstep. Every device simulates every car; tick N
may run only when every seat's input for N is in hand; nothing but inputs
crosses the wire. `LockstepClock` gates ticks, a delay buffer (6 ticks) absorbs
jitter, 16 ticks of redundancy repair loss, `DivergenceWatch` compares state
hashes.

The implementation is now genuinely solid *as lockstep*: agreement holds
through 60% simulated loss, the desync class is fixed (everything the sim reads
travels in `RaceStart`), and eleven device-found bugs are closed and pinned by
tests with latency in them.

## A residual bug, found on the fresh read

**Hash reports still go out one packet per simulated tick**
(`GameSession.step` → `report(hash:at:)` → `transport.send`). The input flood
was fixed to one packet per frame; the hash flood was not. So the wire carries
~120 messages/second per device — and during a catch-up frame, 13 sends are
enqueued in one burst. This is the same class as the freeze the packet-rate fix
addressed, and it is the leading suspect for the remaining symmetric ~2 Hz
stutter: MC's queue congests, delivery clumps, every clump is a stall-and-burst
on *both* sides.

The fix is small either way: piggyback the newest tick's hash onto the input
packet (zero extra packets), or send one hash per N ticks. Worth doing even if
the model changes, because it confirms or clears the transport as the stutter's
cause for one on-device test.

A zero-code check worth doing in the same test: confirm both phones are on the
same Wi-Fi with Bluetooth off. MC silently falls back to peer-to-peer/Bluetooth,
whose latency is bursty in exactly the observed rhythm.

## Why lockstep keeps fighting this product

Three observations, in increasing order of importance.

**1. The transport amplifies its weakness.** MC delivers in bursts under
pressure. Snapshot-based models tolerate bursts natively — the newest snapshot
supersedes, the rest are skipped. Lockstep inverts that: every late clump is a
universal stall followed by a fast-forward, which is precisely the "pause,
jump, pause" seen on device. The model and the transport have opposite grain.

**2. The hardest bug class exists only because of the model.** Of the eleven
device bugs, the desyncs — the ones that each cost a full session — exist
*only* because lockstep requires bit-perfect agreement on every value the sim
reads, forever, including future features. That discipline ("nothing the sim
reads may come from local state") is a permanent tax on all future work: one
new setting read locally, one unseeded random, one libm difference on a future
Mac peer, and the race silently forks again. The golden-hash tripwire guards
it, but the class is structural.

**3. The product owner has rejected the model's defining trade, twice.**
Lockstep never lies and sometimes waits. The stated preference — own car
smooth and responsive, remote cars allowed to warp a little — is not a tuning
of lockstep; it is the definition of a different model. `delayTicks` also puts
33–100 ms between the local thumb and the local car, which no amount of fixing
removes.

## The options

### A. Keep patching lockstep

Fix the hash flood, retest, tune `delayTicks`. Half a day to a verdict. Even
in the best case the result stalls on bad links and keeps own-car input lag —
both already judged unacceptable. Worth doing ONLY as the cheap experiment
bundled with the instrumentation, not as the plan.

### B. Peer-to-peer rollback (GGPO-style)

Every peer predicts, rolls back, and re-simulates on late input. Keeps the
entire determinism burden of lockstep (observation 2 stays forever), adds
snapshot/re-sim machinery on every device, and its sole advantage over option
C — no privileged host — is worthless on a couch. Highest complexity, least
relevant benefit. Not recommended.

### C. Host-authoritative snapshots *(recommended)*

The host simulates the one true race, exactly as local play does today.
Clients send their inputs (the existing 4-byte `CarInputWire`); the host
applies the latest received input for each remote seat — holding the last one
when none is fresh, which is *safe* here because there is nothing to fork: the
host's word is the race. The host broadcasts compact state snapshots
(~28 bytes/car; 4 cars at 20 Hz ≈ 2.5 KB/s, trivial); clients render
interpolated snapshots.

What this buys, structurally rather than by effort:

- **Desyncs become impossible, not merely detected.** No bit-agreement
  requirement, no "everything from the host's message" discipline, no float
  determinism question for a future Mac peer. The whole class closes.
- **Loss and burstiness degrade gracefully.** A late snapshot means remote
  cars interpolate a moment longer; nothing ever stalls. A dropped peer means
  one coasting car, not a frozen race.
- **The host plays with zero added latency** — it IS local play. Late join and
  host-side pause become possible in principle.

What it costs, honestly:

- **Client input latency** (½ RTT to reach the host) and **remote-car warp**
  on correction — the exact trade the product owner asked for.
- **New work**: a compact snapshot codec (same positional style as the input
  packet, ~a day), the host tap (small — `inputFor` was built as an injected
  closure for exactly this), and the client render path (the real work:
  feeding an interpolated snapshot state to the renderer instead of a local
  sim).
- **v2, only if client feel demands it**: client-side prediction of the own
  car with reconciliation. Feasibility is measured, not assumed: a sim tick
  costs 0.19 ms (2 cars) / 0.37 ms (4 cars) in DEBUG on an M-series Mac, so
  re-simulating a ~20-tick window is single-digit milliseconds.

What carries over from the spike: the transport, lobby, roster, `RaceStart`,
input quantisation, all eleven bug fixes in those layers, and the sim's
determinism (it makes prediction accurate). What retires to tests/debug:
`LockstepClock`, `DivergenceWatch`, the delay buffer. The recording/ghost
story is unchanged — the host records inputs exactly as local play does.

## Recommendation

1. **Half a day**: piggyback the hash on the input packet, add an on-screen
   tick-rate/buffer readout, and run one device test on same-Wi-Fi with
   Bluetooth off. This either finishes the lockstep diagnosis or clears the
   transport for the new model — the work is not wasted in either branch.
2. **Then build option C as v1** — no client prediction yet, interpolated
   remote view, measure feel on device.
3. **Add own-car prediction (v2) only if v1's client latency feels bad.**

The lockstep spike did its job: it answered "does inputs-only sync hold on
this hardware" with a measured *no for this product* — not because agreement
fails (it holds through 60% loss), but because the model's defining trade,
stall-rather-than-lie, is the wrong trade for a couch racer on a bursty
transport.
