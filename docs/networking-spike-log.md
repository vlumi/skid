# The two-phone spike: what was found

Step 4 of [networking-plan.md](networking-plan.md), run on two iPhones over
several sessions. This is the record of what actually broke, because most of it
was invisible to the tests and would otherwise be rediscovered.

## Status: not yet playable

**Current symptom: symmetric ~2 Hz pauses on both devices.** Everything below is
fixed and verified, and the race does run — but a steady stutter remains, and its
cause is not yet known.

## What the tests could not see

The single most useful lesson. Five rounds of green tests sat alongside a
stuttering device, because the harness delivered packets **instantly and
synchronously**. That is not a simplified network; it is a different thing that
cannot fail the way a network does — with instant delivery both peers advance
every frame no matter how the code is paced, so a whole class of bug cannot
reproduce.

Every network test now has **latency** in it. With two frames of delivery delay
and *no* packet loss, one bug stalled 154 of 600 frames.

The second lesson: **a test double that conflates two operations cannot see the
difference between them.** The double counted `publish` and `record` identically,
so it measured ticks rather than packets and missed a 4× packet flood.

## The bugs, in the order they were found

| symptom on device | actual cause |
|:--|:--|
| Both lobbies show one device, Start disabled, both think they are host | Roster keyed on `MCPeerID.displayName` — both phones are called "iPhone" |
| Stuck at "3" | `started` is a per-device ready gate; a frozen device publishes nothing, so every peer starves |
| Lobby jams on Start, Back unresponsive | Every MultipeerConnectivity call was on the main thread; `send` and `disconnect` block |
| App freezes the moment the race starts | Per-tick diagnostics were `@Published` and `RaceScreen` observes them — a render loop |
| Both phones show blue and orange; guest steers nothing; "waiting" forever | `CouchRig` hardcoded `PlayerID(index)`, so every device built players 0 and 1 |
| HUD chip blue on both screens | `playerChip` indexed cars and colours by BAND index, not by seat |
| Cars drift apart, desync at a **repeatable** tick (182) | Each device used its own persisted car tuning and `carContact` |
| Constant 2 Hz stutter, banner in time with it | Reliable channel coalesces like TCP: a 60 Hz stream arrives in clumps |
| Steady stutter across *both* channel modes | Publishing keyed off `race.tick`, which needs the peer's input — mutual starvation |
| Two flashes then a pause | Publishing counted frames, assuming steady 60 fps |
| Client smooth then freezes; host waits constantly | One packet **per tick** — ~100 packets/sec, backing up MC's send queue |

## Rules the design now follows

- **Anything the simulation reads comes from the host's `RaceStart`** — track,
  seed, roster, laps, delay, tuning, `carContact`. Local settings stay local to
  what only one screen sees (seating, sound, haptics). Two of these were missed
  and caused the worst bug of the spike.
- **Never index by band, always by seat.** Global seat numbers are sparse; three
  separate bugs came from using a local index where a seat was meant.
- **Nothing calls into MultipeerConnectivity from the main thread.**
- **Nothing per-tick is `@Published`.** `GameSession` documents the same trap.
- **Publishing must not depend on the sim advancing**, or peers starve each other.
- **One packet per frame**, whatever the buffer covers.

## Measurements worth keeping

- Loss tolerance, gapless input with 16 ticks of redundancy: full speed and
  agreement through 60% loss; 80% falls behind; 95% stalls. Agreement never
  breaks, which is the property that matters.
- Delay buffer against a 40 fps peer facing a 60 fps one, no loss: 2 ticks stalls
  200 of 600 frames, 4 ticks none. Set to 6 for margin.
- Packet size: ~133 bytes for a two-seat device at 16 ticks of redundancy; a
  nine-seat field stays inside one datagram.
- `Codable` is not a wire format: a 28-byte packet encodes to 438 bytes of JSON.

## What to try next

1. **Measure the 2 Hz period against something.** It has survived both channel
   modes, sim-time pacing and the packet-rate fix, so it is unlikely to be the
   transport. The trace in the lobby could be extended to log tick rate and
   buffered depth during a race — the readout, not another theory.
2. **Lower `delayTicks` to 4.** The packet rate no longer scales with it, so this
   is now a free experiment.
3. **Reconsider the architecture.** Lockstep stalls whenever any peer is late,
   and the user's instinct — smooth local car, remote cars warping — describes
   prediction with rollback. The groundwork suits it: `Race` is a value type, the
   sim is deterministic, and `stateHash` already detects a bad prediction. It is
   a real rewrite of this layer, not a patch.
