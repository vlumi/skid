# Roadmap

The implementation plan, as **named milestones in rough order**. This file is
*expected to churn* — milestones get reshaped as prototyping answers questions.
Everything before 1.0 is beta by definition (TestFlight from v0.1). As milestones
ship, they drop to the [README version history](README.md#version-history)
(brief) and [CHANGELOG.md](CHANGELOG.md) (full), and this file keeps only open
work. Settled rules, conventions, and design decisions live in
[AGENTS.md](AGENTS.md); this file is only *when*, not *why*.

**Milestones are not version numbers.** A version is assigned when a milestone
is *cut*, not when it is planned — because some of these will be reordered, split,
or dropped outright, and renumbering the rest each time is the churn that stops a
roadmap being updated at all. The networking spike below was exactly that: an
unversioned milestone whose job was to kill or confirm the two after it.

Guiding order: **the drift is the game.** The first milestone existed to answer
"is the driving fun?", and multiplayer-on-one-device came next because it is the
product's heart.

**What comes early is whatever answers a question that changes the plan** — and
the networking spike is the case in point, both for being worth it and for what
it cost. It ran early precisely because the answer reshaped two later milestones,
and the answer was **not the expected one**: inputs-only lockstep held its
agreement but lost to the real link, so the model is host-authoritative snapshots
instead. Cross-device play works, which keeps the platform milestone; and it
works in a way that makes a Mac peer *cheaper* than planned.

The bill is worth remembering when scheduling the next spike: eleven bugs found
only on hardware, most invisible to a passing test suite, because a harness that
delivers packets instantly cannot fail the way a network does. Validation on
device was the right call and was not the cheap one.

**Milestones are small; releases group them.** Each heading below is one
player-visible theme, sized so it could ship alone — and several will travel
together in one version, because a release wants enough in it to be worth a Beta
App Review. The grouping is in *Release grouping* below rather than in the
headings, so reordering a milestone does not mean renumbering anything.

What stays late is the game *around* the race, and the app around that: today a
result evaporates the moment it ends. That is deliberate — and there is one
sequencing fact worth naming, because it is easy to miss when items are scattered:
**the front end blocks more than it looks like.** Colour picking, profiles,
records and a track browser all need surfaces that do not exist yet, so they queue
behind one redesign rather than being four independent tasks.

---

Shipped milestones (v0.1–v0.7) are summarized in the
[README version history](README.md#version-history); full detail is in
[CHANGELOG.md](CHANGELOG.md). This file keeps only open work.

## Release grouping

Rough, and expected to churn — the point is which themes are worth shipping
*together*, not what they will be numbered.

| next | then | later | 1.0 |
|:--|:--|:--|:--|
| Surfaces & hazards | The front end | Platforms & input | Polish & submission |
| Networked play: the tail | Identity & records | More to build with | |
| First ten seconds | | Tournaments & sharing | |

**Why that order.** Surfaces are the biggest remaining change to *how it drives*,
and the sim half is already done. The networking tail is small and finishes work
players are using now. The first-ten-seconds items are cheap and fix a reported
problem. Everything in *The front end* waits on one redesign, so it is one release
whether it is one milestone or four.

## Surfaces & hazards — *how it drives*

The last big change to the driving itself, and the cheapest of its kind left:
`Surface` already carries the grip and drag model, so the sim work is largely
done and what is missing is **placement and the look of a boundary**.

- [ ] **Road surface as a per-piece attribute** (snow, gravel, dirt) — *the
      gameplay half, and the bigger of the two*.
      Better decomposed as an attribute than as a map theme: pitch and rails are
      already per-piece, so a **snow section** or a gravel shortcut is the same
      shape of feature, and it lets one track mix surfaces instead of committing
      the whole map. `Track.surface(at:)` hardcodes `.asphalt` on the ribbon today,
      so this makes that value come from the piece. `Surface` already has the
      grip/drag model; what it lacks is snow/gravel values.
      **The open question is the TRANSITION, not the grip.** A hard boundary reads
      as a cut line, which is what `SurfacePatch` (a circle with a crisp edge) looks
      like today for hazards. A surface change wants to be visually pleasing — a
      scatter or a blended band rather than a seam — and that is a rendering
      problem worth solving once for hazards and surfaces together. Decide whether
      the sim blends too (a transition zone with interpolated grip) or whether only
      the drawing softens while the physics steps: the second is cheaper and
      probably indistinguishable at speed.
- [ ] **Off-road surface — the other half of the same line of code.** Not a
      "theme" at all, once road surface is an attribute: it is what the ground
      *beside* the track is made of. `Track.surface(at:)` returns `.grass` off the
      ribbon exactly as it returns `.asphalt` on it, so the two are one symmetric
      change — and the existing `theme` field's cases are already `normal / snow /
      sand`, which are surface names rather than visual ones. Rename it for what it
      does.
      Whole-map rather than per-piece, unlike the road: sand beside one corner and
      snow beside the next is nonsense, and a single value is what makes "a snow
      rally track" or "a desert circuit" a thing you pick once. It carries the look
      with it (ground colour, grass texture), so it ships alongside decorations —
      the props you place and the ground they stand on are the same feature seen
      from two distances.
- [ ] **Hazards as placeable pieces.** Water/oil/mud left with the old
      hand-authored tracks and needs to come back as something you place.
      Smaller than it looks: `Surface` already has all three tuned, and
      `SurfacePatch` + `surface(at:height:)` already do the sim half — what is
      missing is encoding, editor placement and rendering. Free position rather
      than anchored to a piece, since an oil slick's whole point is sitting at a
      chosen spot on the racing line. Design in
      [docs/hazards-and-scenery-plan.md](docs/hazards-and-scenery-plan.md).

## Networked play: the tail — *finishing what players are using*

Host-authoritative snapshots shipped as v0.7.0 and work; these are the
leftovers, all small. Two of them are *measurements* rather than features, and
should not be built before they are taken.

- [ ] **Choose your colour in the lobby**, from the measured accessible nine,
      with the default assignment being the accessible set (see
      [docs/first-glance-plan.md](docs/first-glance-plan.md) — the palette work is
      done, the picker is not). Under networking a colour must be agreed centrally,
      since "local" is a per-screen property.
- [ ] **Judge the client's input latency on a real link.** Your thumb reaches the
      host and the result comes back a snapshot later; the on-screen
      `gap · lag` readout is the number. If it feels bad, the fix is
      **client-side prediction of the own car with reconciliation** — measured
      feasible (0.37 ms/tick for 4 cars, so a 20-tick re-simulation is
      single-digit milliseconds) and explicitly NOT worth building until the feel
      demands it.
- [ ] **Three or more devices, on hardware.** The logic is proven: a test drives
      three devices and four seats through the real relay and client views under 20%
      loss, and each seat responds to its own device's thumbs. What that cannot
      measure is the radio — MultipeerConnectivity's practical ceiling is around
      eight peers, and the packet budget grows with the field — so this wants a third
      phone in the room, not more tests.
- [ ] **Host pause.** Deliberately unresolved: a per-device pause would freeze one
      screen of a shared race, so today the map tap does nothing when networked.
      Host-only, a vote, or no pause at all is a design question, not a bug.

## The first ten seconds — *what a new player sees*

Reported as three problems and it is one: nothing on screen explains itself when
it matters. Cheap, and each one fixes something a real player hit. Measured and
planned in [docs/first-glance-plan.md](docs/first-glance-plan.md).

The *palette* half already **shipped** with the nine-car grid — the measured
accessible nine, guarded by a minimum-ΔE test. What that plan also found is still
open, and it is first below because it undoes the shipped work.

- [ ] **The sheen eats the palette.** Every car is drawn with a white wash across
      its front half at opacity 0.55, which collapses the palette's worst pair from
      ΔE 24.7 to **9.1** — the same colour once a 20-unit sprite is moving. So the
      drawing gives back what the colours bought. Measured at 0.40 → 12.9 and
      0.25 → 17.0, so toning it down may be the whole fix; tinting the wash with
      the car's own colour is the alternative. Judge it on device, but the ΔE floor
      belongs in a test the way the palette's does.

- [ ] **Two more, both small.**
      - **Which car is mine, on the grid.** A number bubble and a ring during the
        countdown, the number **rotated to face its own player** — the rig already
        knows that vector (`ZoneChrome.up`), and `Race.Phase.countdown` already
        exists to hang it on.
      - **The control pad should be visible before it is touched.** `origin` is nil
        until touch-down today, so the control appears only once you already know
        where to press. Give it a dimmed resting position at the centre of its own
        zone. Note the default scheme is *casual*, so this is the aim stick first.

## More to build with — *the editor's tail*

The editor shipped as v0.6.0. What is left divides cleanly: the first two change
what a track can *be*, the rest are editor conveniences that can ride any build.

- [ ] **Jumps in the compiler** (crossings are DONE). Crossings shipped as
      IMPLICIT — nothing declared, flagged or encoded. A segment pair may share
      tarmac where both stretches are at the same height AND their lines meet at
      ≥ 45°; shallow overlap stays refused. The height half is load-bearing: the
      angle test alone permitted a road crossing a RAMP, which is a solid
      embankment. Shipped with a heading-alignment tiebreak for the resolver in
      the shared zone (measured 1606 units of arc jump per tick before, 14.7
      after). Design and the rejected alternatives are in
      [docs/crossing-plan.md](docs/crossing-plan.md).

      Still open on crossings: gate seams inside a shared zone are permitted,
      pending whether it bites in practice. Elevated crossings are out of scope
      until someone wants a double-decker junction (two decks crossing would each
      throw a rail across the other's lane).

      JUMPS remain: the catalog has the geometry and the editor has the buttons
      hidden, but the compiler cannot build them. Closer than it looks — the
      piece is flagged `launches`, the car has `airborneTicks`, and the flight
      physics is tuned; what is missing is the compiler emitting a launch ramp.

      **Height groundwork comes first**, in
      [docs/height-groundwork-plan.md](docs/height-groundwork-plan.md). Two
      halves: rails, embankments and the mouth gate are three concepts riding on
      one `if` (and a ramp is walled as if it always rises from the GROUND, which
      breaks the moment a 1→2 ramp exists); and flight has no vertical arc at
      all — a fall snaps height to 0 and glides. **Ballistics first**, because
      falls off a deck, off a railless ramp flank, off a banked curve's high side
      and off a jump lip are all one event, and each would otherwise invent its
      own behaviour.

      FORKS AND JOINS ARE PARKED, and not for want of geometry (the catalog has
      the pieces, ids 34–36, and `PieceCompiler` throws
      `forkNotSupportedInPhaseA`). Two reasons, in order:

      - **The canvas is too small to afford them.** A fork only earns its
        complexity if the branches trade off — shorter but tighter against
        longer but faster — and at today's track sizes there isn't room for two
        routes that are meaningfully different. Revisit if
        **Track size classes** (below) lands.
      - **Route choice, not geometry, is the expensive part.** A branching route
        makes the track a graph rather than a ring, and every simplification
        built on that ring breaks at once: `centerline` stops being one array,
        `arcPosition` stops being a single number (position on which branch?),
        lap validity can't be "collect every gate in order" when a branch's
        gates aren't on your path, standings need a progress metric comparable
        across unequal paths, and the AI has to make a choice it currently
        never makes.

      A JOIN alone — a branch merging back in, carrying no gates and required by
      no lap, like a pit lane or an alternate entrance — keeps the lap on the
      trunk ring and skips most of that. That is the cheap half if branching is
      ever wanted before full forks.
- [ ] **Merging and diverging roads.** Parked, with the measurements, in
      [docs/crossing-plan.md](docs/crossing-plan.md): a pinched `)(` eight turns
      out not to be a crossing at all but two roads running alongside for about
      a road and a half before separating, and no threshold on a single overlap
      distinguishes it from a track grazing itself (three were measured and all
      ranked the cases wrongly). Needs its own decisions — what the road looks
      like where two lanes are briefly one, and how the resolver picks a road
      where both agree about direction.
- [ ] **Catalog beyond road pieces.** More road pieces (the palette is still
      small), plus **decorations**: on-road arrows, trees, buildings, walls
      (scenery + directional markers, not just track segments), and **spectator
      dressing** — stands, trackside props, crowd texture, which is the same
      feature: placeable scenery that never touches the sim. Placed in the
      editor. Fold in the **ramp-wall vs deck-rail visual distinction** — a ramp
      wall reaches the ground, a deck rail only exists up top, and today they
      look identical, so where a car can pass underneath isn't readable — that
      one is a pure rendering fix, since the compiler already knows which is
      which, and can ship on its own. Split into tiers, by what each actually
      costs to encode, in
      [docs/hazards-and-scenery-plan.md](docs/hazards-and-scenery-plan.md).
- [ ] **Track size classes.** Bigger canvases for bigger screens: a track
      declares its size, and the oversized ones are iPad/Mac-only. Lets much
      more elaborate courses exist without making them unplayable on a phone.
- [ ] **The editor overhaul — step 7 only** (chrome relocations). Steps 1–6 have
      shipped; the plan and every settled decision are in
      [docs/editor-overhaul-plan.md](docs/editor-overhaul-plan.md).

      Done: one mutation API remapping `gateSeams`/`fitters`/`pitches`/`decals`
      together (identity, not index); prepend and delete-anywhere-on-a-ring
      (rotate-then-pop, so the surviving road stays put by construction); undo
      and redo over encoded snapshots; gating as its own MODE, which resolved the
      seam-tap vs piece-tap conflict outright; piece selection, with delete on
      the selection and the build end as a property of the selected end;
      in-place decal variants; and reversing the driving direction.

      Left: **step 7**, the chrome — where the closure control lands, the "track
      complete" chip out of the button column. Explicitly a decide-on-device
      step, once everything above has been driven.

      Also still open from step 6: a **long-press variant picker**, for deleting
      and reassigning the start line. Reversing the driving direction shipped
      without it (#108) — as a whole-track transform on the LAYOUT, not the
      compiler flag this plan sketched.
- [ ] **Height readout on the map.** A tiny label on each piece showing its
      height, behind a show/hide toggle — building in three dimensions from a
      top-down view means the numbers are otherwise only inferable from shading.
- [ ] **Import a track by link or QR.** Signing and the library both **shipped**
      in v0.6.0 — Ed25519 attribution with the keypair in the iCloud-synced
      Keychain, and many named tracks replacing the one "My track" slot. What is
      left of that plan is getting a track in from *outside* the app: the clipboard
      works today, and a tapped link or a scanned code is the version a player
      would use. Measured then: a signed code is 120–140 bytes, which fits QR V8/V9
      comfortably. The settled encoding decisions are in
      [docs/track-pieces.md](docs/track-pieces.md), including why a track's *name*
      stays local — a signed name could not be renamed after import — and rides as
      an unsigned URL parameter when this lands.

## The front end — *the app around the race*

**The current UI is a harness, not a design**, and it is the gate in front of
several other features: a colour picker, a profile, a records screen and a track
browser all need surfaces that do not exist. That is why they are one milestone
rather than four.

- [ ] **UI and menu redesign — the whole surface.** The current UI is a harness,
      not a design: the app is three phases (setup → racing → editing) with a
      single flat setup screen, no results screen, no menu hierarchy, no track
      browser, and settings scattered between setup and a pause-menu Tuning panel
      that was only ever meant for on-device A/B tests. It shows: `SetupView`
      still switches on the names of tracks that no longer exist. Redesign it as
      a product — a real front end, a track browser (needs the library from the editor milestone),
      results and records screens, a settings home, and the editor reachable as a
      first-class destination rather than a button on the setup sheet. **This is
      the bulk of the milestone**, and it's the natural home for the deferred
      **pause-menu cleanup** (including per-player scheme changes mid-race) and
      for splitting the dev-only Tuning dials out of the player-facing settings.

## Identity & records — *the race outlives itself*

Needs the front end above to have somewhere to put it. The data is closer than it
looks: per-track bests and full ghost recordings already persist, keyed by track
id — what is missing is tying a result to a *person*.

- [ ] **Local player profiles.** A chosen name at minimum, on-device only (no
      accounts, no server — see "out of scope"). Everything below hangs off
      this, which is why it's first. Open question: allow ad-hoc anonymous
      players, or make everyone pick a name up front?
- [ ] **Records that stick, and are worth looking at.** Best lap and best race
      already persist per track; make them visible and per-profile — a results
      screen worth reading, "you beat your best" in the moment, and a per-track
      board of who on this device holds what.

## Tournaments & sharing — *a reason to keep playing*

- [ ] **Tournaments.** A series of races across one or more couch sessions, with
      standings per profile. Also *unlocks* the **reverse-standings grid** (race
      N starts in reverse order of the standings after N−1, worst on pole; ties
      broken by the seeded RNG), which is blocked today purely for lack of a
      cross-race standings layer. Decide: fixed cups, or pick-your-own series?
- [ ] **Send a time to a friend.** A ghost is a seed plus an input stream, so
      it's small — the same trick as a track code. Share a time as a link/QR,
      import it, and race against their ghost on your device. Needs the track
      identity from the library work, so the two ends agree on which course a
      time belongs to. **This is the closest thing to online play that stays
      within "no server":** asynchronous, peer-shared, no accounts. Landing after
      the networking work means the track-identity and transport questions are already answered.
- [ ] **Career ladder** with cosmetic-only unlocks (liveries, effects) to show
      off when racing others — never performance. Wants profiles and tournaments
      under it first.

## Platforms & input — *the other ways in*

The game runs one way on one kind of device: portrait, on a phone, driven by
thumbs on glass. Cross-device play works, so a Mac target has its purpose — and
it got *cheaper* than planned, since a Mac joining as a rendering client needs no
float determinism from its libm, which was the one real cross-platform risk.

- [ ] macOS target (Universal Purchase, same bundle id), sim untouched —
      only render/input capture differ
- [ ] Keyboard scheme (arrows/WASD, 1–2 players) and GameController support
      as additional `ControlSource`s
- [ ] **Landscape mode (couch).** Turn the phone and the *whole game*
      reorients 90° — map, HUD, and each player's control/steering frame —
      but the touch **zones stay pinned to the same physical device regions**
      (thumbs don't move; zones are device-space, not UI-space). Payoff: wide
      tracks align with the long axis → bigger map. **Lock orientation during
      a race** (settle it before the race, freeze it — a mid-drift flip is
      chaos); unlock in menus.
- [ ] **iPad & landscape map-sizing policy.** Grow `fittedMapRect` from pure
      edge-to-edge fit into a policy: phone = fit-to-width (current); **iPad =
      cap the map at a comfortable size and reserve *more* for controls** (big
      screen ≠ giant map, map floats with margins); **landscape = bands dock
      left/right** of the map (free space is on the sides), which needs
      `CouchRig` side-band support (today it only does top/bottom).

## Polish & submission — *this one is 1.0 by definition*

- [ ] **Raise the field cap, or keep it.** `CouchGame.maxCars` is a **soft cap of
      4** while the engine seats 9: the grid, the palette and the sim all handle a
      full nine-car field (pinned by `FullFieldTests`), but how nine behave on a
      real phone is unmeasured. Raising it is one number.
      Measured so far, all in a DEBUG simulator build and so not device-truth: on
      the clover at 9 cars the sim costs ~7–11 ms/tick against a 16.7 ms budget,
      and **cars that actually drive cost 58% more than cars sitting still**
      (10.94 vs 6.92 ms) — so the cost tracks how many cars are *racing*, not how
      many exist. Which is why 4 players + 5 AI felt fine while 1 + 8 did not: with
      four seats and one driver, three cars barely move.
      Note `GameSession.maxTicksPerFrame` is 12, so one late frame costs up to 12
      ticks and stutter compounds — worth looking at first if choppiness returns.
- [ ] **Final polish & balancing pass.** With all content and controls
      settled, do the tuning that only makes sense at the end: **bake the
      final control-feel dials** (the aim-drift model + defaults shipped in
      v0.5; the live dials let this wait), **balance** the tracks / AI /
      difficulty, and sweep the remaining rough edges. This is why the
      control-feel tune was deferred here.
- [ ] **Decide the fate of every experimental flag.** A flag with no verdict is
      the failure mode — it accumulates code paths nobody drives. For each one:
      promote it (delete the condition, ship the controls) or remove it (delete
      the controls; the format keeps its pieces, since a track someone already
      built and shared must not stop working). See
      [docs/experimental-features.md](docs/experimental-features.md).
      - **Gaps and warps** (`SKID_EXPERIMENTAL`). The physics shipped and are
        unconditional; what is parked is the *authoring*. A warp is invisible
        and adjusted by arrows that act on wherever you happen to be building,
        and a gap is a piece made of nothing — both need explaining on a palette
        that is otherwise "tap a shape". **Worth a fresh UI/UX attempt before
        deciding**: the pieces work and race fine, so this is a question about
        the editor rather than about the feature.
- [ ] Icon polish pass (light/dark/tinted variants — the base icon ships with
      every build already)
- [ ] One ASC record (Universal Purchase), listing text + screenshots,
      privacy/age answers
- [ ] Submit, await review, release (release lane already live since
      v0.5.0 — see [RELEASING.md](RELEASING.md))

## Backlog (unversioned)

- [ ] Full replay viewer (watch/scrub any stored run — the data exists from
      v0.2). Sharing a run as a ghost is in the real-game milestone.
- [ ] Full vertical loops — the crazy one; only if bridges and jumps prove fun
      (and readable) in play. Note elevation is now a continuous height, not two
      layers, so a loop is no longer obviously outside the model.
- [ ] Procedural track variations (the editor's piece catalog could seed
      these) — a maybe, not a commitment
- [ ] Damage/pickup mischief (dropped oil, turbo) — only if the core race
      wants more chaos
- [ ] Finnish/Japanese localization (String Catalog makes this
      translation-only)
- [ ] **Different vehicles** — maybe; only if they stay balance-neutral
      (distinct look/feel, same competitive envelope)
- [ ] *(Parked)* **Portable profiles**: bring your profile to someone else's
      iPad and carry results home, cryptographically owned so nobody can claim
      your player. Unsolved: nothing stops the same profile "playing" on two
      devices at once. Now that profiles land *after* networked play, revisit it
      there — if your device is your identity on the network,
      this may be moot.

## Deliberately out of scope

Per [AGENTS.md](AGENTS.md): no ads, no IAP, no accounts, no server, no global
leaderboards, no third-party runtime dependencies. Networked play is
peer-to-peer on the local network only. watchOS/visionOS/tvOS not targeted.
No performance tuning or upgrades — cosmetic unlocks only (see AGENTS.md for
the why).
