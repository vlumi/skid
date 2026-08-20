# Roadmap

The implementation plan, as **named milestones in rough order** — and *only open work*. This file is *expected to churn*: milestones get reshaped as prototyping answers questions, and everything before 1.0 is beta by definition (TestFlight from v0.1). As work ships it leaves this file — brief summaries go to the [README version history](README.md#version-history), full detail to [CHANGELOG.md](CHANGELOG.md), and settled rules and design decisions to [AGENTS.md](AGENTS.md) or the plan under [docs/](docs/) that owns them. This file is only *when*, not *why*.

**No hard line wraps** — one paragraph or bullet, one line; editors soft-wrap and rendered Markdown ignores the breaks anyway.

**Milestones are not version numbers.** A version is assigned when a milestone is *cut*, not when it is planned — some of these will be reordered, split, or dropped outright, and renumbering the rest each time is the churn that stops a roadmap being updated at all.

Guiding order: **the drift is the game**, and **what comes early is whatever answers a question that changes the plan**.

## Release grouping

Rough, and expected to churn — the point is which themes are worth shipping *together*, not what they will be numbered.

| next | then | later | 1.0 | parked |
| --- | --- | --- | --- | --- |
| Tournaments & sharing | Networked play: the tail | More to build with | Polish & submission | Surfaces & hazards |
| First ten seconds: the tail | The front end: the tail | Platforms & input | | |

The **track library** sits inside *Tournaments & sharing* but depends on nothing — it is design work, not code, and can start at any time. It gates tournaments.

**Why that order.** The front end shipped in v0.8 — the opening screen answers who is playing and what to do, profiles and record boards keep results, and settings/about/results all have homes — which unblocks what queued behind it. Tournaments are the next genuinely new thing: the one mode that gives a five-second lap a reason to be driven forty times, gated by the track library. The structure is in [docs/game-shape-plan.md](docs/game-shape-plan.md).

## Surfaces & hazards — *PARKED*

**Parked until the game is more finished.** The guard worth keeping, because it caught the same feature twice: each of these is **cheap to build and unproven to matter** — "the sim half is already done" is a statement about cost, not value. A lap is 5–10 seconds on a track the player can see all of and will drive forty times, so surface variety is a change every second or so with nothing to learn about it, and it is ~47 authoring decisions per track.

One exception survives, and it belongs to the library rather than here: *some* decoration before 1.0, so a dozen tracks do not all read as the same asphalt ribbon on the same green — about tracks having character, not how they drive. See [docs/game-shape-plan.md](docs/game-shape-plan.md). What is missing if any of the rest is ever built: **placement and the look of a boundary**.

- [ ] **Road surface as a per-piece attribute** (snow, gravel, dirt) — the gameplay half. Better an attribute than a map theme: pitch and rails are already per-piece, so a snow section or a gravel shortcut is the same shape of feature, and one track can mix surfaces. `Track.surface(at:)` hardcodes `.asphalt` on the ribbon; `Surface` has the grip/drag model and lacks only snow/gravel values. **The open question is the TRANSITION, not the grip**: a hard boundary reads as a cut line, so a surface change wants a scatter or blended band — worth solving once for hazards and surfaces together. Decide whether the sim blends too, or only the drawing softens while the physics steps (cheaper, probably indistinguishable at speed).
- [ ] **Off-road surface — the other half of the same line of code.** What the ground *beside* the track is made of: `Track.surface(at:)` returns `.grass` off the ribbon exactly as it returns `.asphalt` on it, so the two are one symmetric change — and the existing `theme` field's cases are already `normal / snow / sand`, which are surface names; rename it for what it does. Whole-map rather than per-piece (sand beside one corner and snow beside the next is nonsense), and it carries the look with it, so it ships alongside decorations.
- [ ] **Hazards as placeable pieces.** Water/oil/mud left with the old hand-authored tracks and needs to come back as something you place. Smaller than it looks: `Surface` has all three tuned and `SurfacePatch` + `surface(at:height:)` do the sim half — missing are encoding, editor placement and rendering. Free position, not anchored to a piece: an oil slick's whole point is sitting at a chosen spot on the racing line. Design in [docs/hazards-and-scenery-plan.md](docs/hazards-and-scenery-plan.md).

## Networked play: the tail — *finishing what players are using*

All small, and two of them are *measurements* rather than features — do not build before they are taken.

- [ ] **Judge the client's input latency on a real link.** Your thumb reaches the host and the result comes back a snapshot later; the on-screen `gap · lag` readout is the number. If it feels bad, the fix is **client-side prediction of the own car with reconciliation** — measured feasible (0.37 ms/tick for 4 cars, so a 20-tick re-simulation is single-digit milliseconds) and explicitly NOT worth building until the feel demands it.
- [ ] **Three or more devices, on hardware.** The logic is proven under simulated 20% loss; what tests cannot measure is the radio — MultipeerConnectivity's practical ceiling is around eight peers and the packet budget grows with the field — so this wants a third phone in the room, not more tests.
- [ ] **Host pause.** Deliberately unresolved: a per-device pause would freeze one screen of a shared race, so today the map tap does nothing when networked. Host-only, a vote, or no pause at all is a design question, not a bug.

## The first ten seconds — *what a new player sees*

Nothing on screen should need explaining when it matters. Most of this shipped (the accessible palette, pick-your-own-color with first-come claiming that also holds under networking, the reversing mark, the headlight cone, the tapered nose); measured and planned in [docs/first-glance-plan.md](docs/first-glance-plan.md). What remains:

- [ ] **Two-tone cars — the cost is measured.** A second body color only works as a genuinely distinct hue — a light/dark shade of the base was tried and reverted (worst cross-car patch pair fell to ΔE 4.6, against 24.7 for one tone). The budget is **tones, not cars**: two hues per car needs 2N mutually-distinct tones and nine is already the edge of color-blind-safe spread, so **4 cars two-toned is fine (26.3), 9 is impossible** — a picker feature where field size bounds the selectable pairs, not arithmetic in the renderer. `CarLiveryRenderTests.testCarsStayDistinctAcrossEveryToneTheyWear` has the one-line hook to extend and will hold whatever lands to the same floor.

## More to build with — *the editor's tail*

The first two change what a track can *be*; the rest are conveniences that can ride any build.

- [ ] **Jumps in the compiler.** The catalog has the geometry and the editor has the buttons hidden, but the compiler cannot emit a launch ramp — the piece is flagged `launches`, the car has `airborneTicks`, and the flight physics is tuned. **Height groundwork comes first** ([docs/height-groundwork-plan.md](docs/height-groundwork-plan.md)): rails, embankments and the mouth gate are three concepts riding on one `if` (and a ramp is walled as if it always rises from the GROUND, which breaks the moment a 1→2 ramp exists), and flight has no vertical arc at all — **ballistics first**, because falls off a deck, a railless ramp flank, a banked curve's high side and a jump lip are all one event.

      Crossings shipped as implicit geometry — design and rejected alternatives in [docs/crossing-plan.md](docs/crossing-plan.md). Still open there: gate seams inside a shared zone are permitted, pending whether it bites in practice; elevated crossings are out of scope until someone wants a double-decker junction.

      **Forks and joins are parked**, and not for want of geometry (the catalog has the pieces, ids 34–36; `PieceCompiler` throws `forkNotSupportedInPhaseA`). Two reasons, in order: **the canvas is too small to afford them** — a fork only earns its complexity if the branches trade off, and today's track sizes have no room for two meaningfully different routes (revisit if **Track size classes** lands); and **route choice, not geometry, is the expensive part** — a branching route makes the track a graph rather than a ring, and every simplification built on the ring breaks at once (`centerline`, `arcPosition`, gate-order lap validity, cross-path standings, an AI that never chooses). A JOIN alone — a branch merging back in, carrying no gates, like a pit lane — keeps the lap on the trunk ring and is the cheap half if branching is ever wanted first.
- [ ] **Merging and diverging roads.** Parked, with the measurements, in [docs/crossing-plan.md](docs/crossing-plan.md): a pinched `)(` eight is not a crossing but two roads running alongside before separating, and no overlap threshold distinguishes it from a track grazing itself (three were measured; all ranked the cases wrongly). Needs its own decisions — what the road looks like where two lanes are briefly one, and how the resolver picks a road where both agree about direction.
- [ ] **Catalog beyond road pieces.** More road pieces (the palette is still small), plus **decorations**: on-road arrows, trees, buildings, walls, and **spectator dressing** — placeable scenery that never touches the sim, placed in the editor. Fold in the **ramp-wall vs deck-rail visual distinction** — a ramp wall reaches the ground, a deck rail only exists up top, and today they look identical, so where a car can pass underneath isn't readable; pure rendering, the compiler already knows which is which, can ship alone. Tiers by encoding cost in [docs/hazards-and-scenery-plan.md](docs/hazards-and-scenery-plan.md).
- [ ] **Track size classes.** Bigger canvases for bigger screens: a track declares its size, and the oversized ones are iPad/Mac-only — much more elaborate courses without making them unplayable on a phone.
- [ ] **Import a track by link or QR.** The clipboard works today; a tapped link or a scanned code is the version a player would use. Measured: a signed code is 120–140 bytes, which fits QR V8/V9 comfortably. The settled encoding decisions are in [docs/track-pieces.md](docs/track-pieces.md), including why a track's *name* stays local and rides as an unsigned URL parameter.

## The front end: the tail — *what the v0.8 redesign left open*

The redesign itself shipped: the opening screen (who is playing, then what to do), profiles, settings and about homes, the results card, record boards in the track picker, and the dev tuning dials moved out of the player's pause menu behind the shake gesture. The track browser shipped too, as the editor's track shelf — preview cards, new / start-a-copy (built-ins included) / rename / delete. What is left:

- [ ] **Per-player scheme changes mid-race.** A seat picks Casual or Pro in setup but cannot change once racing — the deferred remainder of the pause-menu cleanup. Per player, not global: one couch mixes schemes.

## Tournaments & sharing — *a reason to keep playing*

- [ ] **Make the track library a channel, not a fixed set.** The dependency nobody scheduled, and the one that decides whether tournaments feel good: **a series is only as good as the tracks it draws from**, and four built-ins means every five-race series repeats itself, which no scoring rule fixes. **Sharing is the leverage**: hand-authoring is the floor — six to eight built-ins, because a tournament needs a pool present on first launch — but every hand-made track costs a design session *and an app release*, while a track that travels as a link or QR code can come from the site, a friend, or a player. Plan: [docs/track-sharing-plan.md](docs/track-sharing-plan.md). The whole track rides in the link (`skid.misaki.fi/t/<code>`), so nothing needs a server and a link cannot rot; previews are needed in the app anyway, and `EditorRenderer.drawTrack` already draws a layout at any scale — a curated collection on the site is static content, and **anyone may host their own**; the design privileges no domain. The hand-authored floor is authorship, not engineering: aim for a deliberate spread — short/technical through long/fast, a couple that climb.
- [ ] **Tournaments.** A series of races across one or more couch sessions, with standings per profile. Also *unlocks* the **reverse-standings grid** (race N starts in reverse order of the standings after N−1, worst on pole; ties broken by the seeded RNG), blocked today purely for lack of a cross-race standings layer. Open, with a leaning each: length (3/5/7, tracks drawn from the library with a re-draw before starting); **points rather than cumulative time**, so one bad race does not end the series for a couch; and it **must survive quitting**, or a five-race series on a phone is unfinishable. Needs the library item above first. See [docs/game-shape-plan.md](docs/game-shape-plan.md).
- [ ] **Send a time to a friend.** A ghost is a seed plus an input stream, so it's small — the same trick as a track code. Share a time as a link/QR, import it, race their ghost on your device. Needs the track identity from the library work, so the two ends agree which course a time belongs to. **The closest thing to online play that stays within "no server"**: asynchronous, peer-shared, no accounts.
- [ ] **Career ladder** with cosmetic-only unlocks (liveries, effects) to show off when racing others — never performance. Wants profiles and tournaments under it first.

## Platforms & input — *the other ways in*

The game runs one way on one kind of device: portrait, on a phone, driven by thumbs on glass. Cross-device play works, so a Mac target has its purpose — and a Mac joining as a rendering client needs no float determinism from its libm, which was the one real cross-platform risk.

- [ ] **macOS target** (Universal Purchase, same bundle id), sim untouched — only render/input capture differ. `SkidKit` already declares `.macOS(.v14)` and neither renderer imports UIKit, so this is less than it looks. **Also unlocks the track-preview generator**: a Mac build links the renderer already, so rendering a code to a PNG becomes a render mode on that target rather than a second executable — see [docs/track-sharing-plan.md](docs/track-sharing-plan.md).
- [ ] **Keyboard scheme** (arrows/WASD, 1–2 players) and GameController support as additional `ControlSource`s.
- [ ] **Landscape mode (couch).** Turn the phone and the *whole game* reorients 90° — map, HUD, and each player's control/steering frame — but the touch **zones stay pinned to the same physical device regions** (thumbs don't move; zones are device-space, not UI-space). Payoff: wide tracks align with the long axis → bigger map. **Lock orientation during a race** (settle it before the race, freeze it — a mid-drift flip is chaos); unlock in menus.
- [ ] **iPad & landscape map-sizing policy.** Grow `fittedMapRect` from pure edge-to-edge fit into a policy: phone = fit-to-width (current); **iPad = cap the map at a comfortable size and reserve *more* for controls**; **landscape = bands dock left/right** of the map, which needs `CouchRig` side-band support (today it only does top/bottom).

## Polish & submission — *this one is 1.0 by definition*

- [ ] **Raise the field cap, or keep it.** `CouchGame.maxCars` is a **soft cap of 4** while the engine seats 9: the grid, the palette and the sim all handle a nine-car field (pinned by `FullFieldTests`), but how nine behave on a real phone is unmeasured; raising it is one number. Measured so far (DEBUG simulator, so not device-truth): ~7–11 ms/tick at 9 cars against a 16.7 ms budget, and **cars that actually drive cost 58% more than cars sitting still** — the cost tracks how many cars are *racing*. Note `GameSession.maxTicksPerFrame` is 12, so one late frame costs up to 12 ticks and stutter compounds — look there first if choppiness returns. **Past nine is a per-track question**: `StartGrid` already lays out any count, so `Grid.slots` and the start piece's depth are what bind — capacity becomes a property of the track, and the palette would need extending past nine to match.
- [ ] **Final polish & balancing pass.** With all content and controls settled, do the tuning that only makes sense at the end: **bake the final control-feel dials** (the aim-drift model + defaults shipped in v0.5; the live dials let this wait), **balance** the tracks / AI / difficulty, and sweep the remaining rough edges.
- [ ] **Decide the fate of every experimental flag.** A flag with no verdict accumulates code paths nobody drives: for each, promote it (delete the condition, ship the controls) or remove it (delete the controls; the format keeps its pieces, since a shared track must not stop working). See [docs/experimental-features.md](docs/experimental-features.md). In particular **gaps and warps** (`SKID_EXPERIMENTAL`): the physics shipped and are unconditional; what is parked is the *authoring* — a warp is invisible and adjusted by arrows acting on wherever you happen to be building, and a gap is a piece made of nothing. **Worth a fresh UI/UX attempt before deciding**: the pieces work and race fine, so this is an editor question, not a feature question.
- [ ] **Icon polish pass** (light/dark/tinted variants — the base icon ships with every build already).
- [ ] One ASC record (Universal Purchase), listing text + screenshots, privacy/age answers.
- [ ] Submit, await review, release (release lane already live — see [RELEASING.md](RELEASING.md)).

## Backlog (unversioned)

- [ ] Full replay viewer (watch/scrub any stored run — the data exists from v0.2). Sharing a run as a ghost is in *Tournaments & sharing*.
- [ ] Full vertical loops — the crazy one; only if bridges and jumps prove fun (and readable) in play. Elevation is now a continuous height, not two layers, so a loop is no longer obviously outside the model.
- [ ] Procedural track variations (the editor's piece catalog could seed these) — a maybe, not a commitment.
- [ ] Damage/pickup mischief (dropped oil, turbo) — only if the core race wants more chaos.
- [ ] Finnish/Japanese localization (String Catalog makes this translation-only).
- [ ] **Different vehicles** — maybe; only if they stay balance-neutral (distinct look/feel, same competitive envelope).
- [ ] *(Parked)* **Portable profiles**: bring your profile to someone else's iPad and carry results home, cryptographically owned. Unsolved: nothing stops the same profile "playing" on two devices at once. If your device is your identity on the network, this may be moot.

## Deliberately out of scope

Per [AGENTS.md](AGENTS.md): no ads, no IAP, no accounts, no server, no global leaderboards, no third-party runtime dependencies. Networked play is peer-to-peer on the local network only. watchOS/visionOS/tvOS not targeted. No performance tuning or upgrades — cosmetic unlocks only (see AGENTS.md for the why).
