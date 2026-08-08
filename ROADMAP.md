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
roadmap being updated at all. One milestone below is explicitly a spike that may
kill the two after it; that cannot have a version.

Guiding order: **the drift is the game.** The first milestone existed to answer
"is the driving fun?", and multiplayer-on-one-device came next because it is the
product's heart.

**What comes early now is whatever answers a question that changes the plan.**
Networking used to sit late, on the reasoning that lockstep is designed in from
the first line of the sim rather than bolted on. That reasoning is sound and is
exactly why the *validation* should be early and cheap: if inputs-only sync over
a local network does not hold up, the Mac port and landscape/iPad work lose most
of their point, and two milestones' worth of plans need rewriting. Better to know
that before building them than after.

What stays late is the game *around* the race, and the app around that. Today a
result evaporates the moment it ends, and the UI is a harness built to reach the
technology rather than a design. **The Real Game milestone is both** — the front
end plus profiles, records and tournaments — deliberately after the technical
foundation, since a menu redesign wants to know what it is presenting and shared
times lean on identity and transport decisions the earlier work settles.

---

Shipped milestones (v0.1–v0.5) are summarized in the
[README version history](README.md#version-history); full detail is in
[CHANGELOG.md](CHANGELOG.md). This file keeps only open work.

## Track editor & shareable tracks — *in progress, cuts as v0.6.x*

> **The one milestone that keeps a version**, because it is already shipping in
> builds. It is also far bigger than the rest: most of it has landed, and what
> remains below is deliberately ordered so it can be **cut in several builds**
> rather than held for a single release. Nothing here blocks the spike that
> follows.
>
> **What is left divides into two kinds, and they are worth telling apart.**
>
> *Changes how the game plays* — **hazards** are the big one, and closer than they
> look: `Surface` already carries mud, water and oil with tuned grip, so the sim
> side is done and only *placement* is missing. Narrower road (a bottleneck) is the
> other, planned in
> [docs/narrow-road-plan.md](docs/narrow-road-plan.md).
>
> **Surfaces are the biggest single item left**, and they are one change wearing
> two hats. `Track.surface(at:)` has a single line that returns `.asphalt` on the
> ribbon and `.grass` beside it, and every track's feel derives from those two
> constants. Make the first **per-piece** (a snow section, a gravel shortcut — pitch
> and rails are already per-piece) and the second **whole-map** (sand beside one
> corner and snow beside the next is nonsense). What was filed as "map themes" is
> really the second one: the ground outside the track, which happens to carry the
> palette with it.
>
> *Changes how the game looks* — **decorations** (the roadmap's own words: "never
> touches the sim"). The largest purely *visible* change left, and the one most
> likely to make the game feel finished rather than prototyped — and because it
> cannot break a race, it is safe to defer and safe to ship in pieces.
>
> All three matter. The distinction is what each one needs before it can ship: a
> hazard and a theme need testing against the driving, a tree needs looking at.

Hand-authoring track geometry hit its quality ceiling; a **phone-first**
editor with a small piece catalog is the answer, and its data becomes the
sharing format. Design settled — see [docs/track-pieces.md](docs/track-pieces.md).

Most of this milestone has landed: the piece model, the editor, share codes,
continuous-height bridges, the built-ins rebuilt from pieces (the old free-form
`TrackDesign` path is gone, so there is now exactly one track engine), flexible
tracks (start line as a piece, canonical codes, the fitting piece), at-grade
crossings, decals on laid pieces, and the editor overhaul bar its chrome pass.
What's left:

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
- [ ] **Track size classes.** Bigger canvases for bigger screens: a track
      declares its size, and the oversized ones are iPad/Mac-only. Lets much
      more elaborate courses exist without making them unplayable on a phone.
- [ ] **Track signing, then a real track library.** Signing comes first, to see
      its real impact on the sharing flow: Ed25519 attribution, `PUBKEY = 254`
      and `SIG = 255` at the top of the tag range, keypair in the iCloud-synced
      Keychain. Attribution, not integrity — anyone can strip a signature and
      re-sign as themselves. Then the library: many named tracks with UUID
      identity, replacing the one "My track" slot, with names kept local rather
      than in the code. Import by link/QR after that; clipboard works today.
      See docs/track-pieces.md for the settled decisions.
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

- [ ] **First-glance usability — the first ten seconds.** Three reported problems
      that are one bug from the player's side: nothing on screen explains itself
      when it matters. Measured and planned in
      [docs/first-glance-plan.md](docs/first-glance-plan.md).
      - **Car colours too close together.** Red vs pink is ΔE 21 in CIELAB — the
        same colour once a 20-unit sprite is moving. Swap pink for magenta and
        keep the palette honest with a minimum-distance TEST, since it is
        arithmetic rather than taste.
      - **Which car is mine, on the grid.** A number bubble and a ring during the
        countdown, the number **rotated to face its own player** — the rig already
        knows that vector (`ZoneChrome.up`), and `Race.Phase.countdown` already
        exists to hang it on.
      - **The control pad should be visible before it is touched.** `origin` is nil
        until touch-down today, so the control appears only once you already know
        where to press. Give it a dimmed resting position at the centre of its own
        zone. Note the default scheme is *casual*, so this is the aim stick first.
- [ ] **Height readout on the map.** A tiny label on each piece showing its
      height, behind a show/hide toggle — building in three dimensions from a
      top-down view means the numbers are otherwise only inferable from shading.

## Networking spike — *does lockstep hold over a local network?*

**A spike, not a feature, and deliberately the next thing after the editor.** No
version: its output is a yes/no that decides whether the two milestones after it
are worth building.

The sim was written for this from the first line — fixed 60 Hz tick, integer/exact
track geometry, inputs-only state, and a determinism suite that already replays
races bit-for-bit (`DeterminismTests`, plus per-feature determinism tests for the
AI, aim drift, contact and elevation). So the question is not "can the sim be made
deterministic" but **"does inputs-only sync survive a real network"**: latency,
jitter, a peer that stalls, a peer that joins late, two devices on different
hardware.

The build order and the scope decisions are in
[docs/networking-plan.md](docs/networking-plan.md) — **iOS first (two phones, so a
divergence is a protocol bug rather than a platform question), up to 4 players per
device, 8 total.** The cap is a **palette** limit rather than a geometric one: the
grid packs 3 abreast × 3 rows = 9 inside the existing start piece (the current
2-abreast layout wastes 36 units of air between the pair), so tarmac is not the
constraint — telling eight colours apart is. A device is not a player: it is a
screen with some players at it, which `CouchRig` already models.

Groundwork, transport options and the packet-loss analysis are in
[docs/networking-groundwork.md](docs/networking-groundwork.md). Three things are
worth doing **before** the spike, each useful on its own: a per-tick `Race`
state hash (which also sharpens the existing determinism tests — they currently
say *that* two runs differ, not *when*), quantised inputs on the wire (also
shrinks ghosts), and a written-down float-determinism assumption with a
cross-device check, since the sim uses `sin`/`cos`/`atan2` on its hot path and
IEEE-754 does not pin transcendentals.

- [ ] **Two devices, one race, inputs over MultipeerConnectivity.** The
      smallest thing that answers the question: no lobby, no polish, no join
      flow — one host, one peer, hardcoded if need be. **MC rather than
      Network.framework because it is not LAN-only** — it falls back to
      peer-to-peer Wi-Fi/Bluetooth, so two phones with no router still find each
      other, which matters more for a couch game than throughput. Keep the
      protocol transport-independent so UDP stays an escape hatch.
- [ ] **Prove or break bit-identical divergence.** Log a per-tick checksum of
      the sim state on both peers and compare. A divergence here is the whole
      point of the spike; finding one late would invalidate the transport
      design, not just the UI around it.
- [ ] **Measure what the couch actually needs.** Input delay that still feels
      like driving, and behaviour when a peer drops mid-race. Lockstep turns
      packet loss into **input lag, not teleporting cars** — no peer can simulate
      a tick until every input for it has arrived — so the knobs are redundant
      input sends and how far behind the newest input the sim runs. Provoke it
      deliberately rather than hoping.
- [ ] **Write the verdict down**, whichever way it goes — as a
      `docs/*-plan.md` with the measurements, so the decision is reviewable
      rather than remembered.

**What the answer changes.** If lockstep holds, the two milestones below are worth
their cost and the Mac port has a purpose beyond "it runs on a Mac". If it does
not, then cross-device play is off the table and **the Mac port and the
landscape/iPad work should be re-argued on their own merits** — they were partly
justified as groundwork for a networked room, and without that they are a smaller,
optional platform nicety.

Spiking early is affordable precisely because the sim is already lockstep-shaped:
this is transport and clock work against an engine that does not have to change.

## Platforms & input — *scope depends on the spike*

The game only runs one way on one kind of device: portrait, on a phone, driven
by thumbs on glass. This milestone is about the OTHER ways in.

**Re-argue this if the spike says no.** A Mac target was always partly a means to
an end — a keyboard player joining a couch race — so if cross-device play is dead,
what is left is a standalone Mac build and a bigger-screen layout, which may or may
not earn a milestone of their own.

This used to sit *before* networking, on the reasoning that a Mac joining a race
needs a keyboard scheme to exist and a locked orientation is one less thing to
synchronise. Both still true — but they are reasons the *full* networking milestone
wants this first, not the spike, which needs two phones and no new input scheme at
all.

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

## Local-network multiplayer — *only if the spike says yes*

The product version of what the spike proved: the room, the flow, and the edge
cases, on a transport already known to work.

- [ ] Deterministic lockstep over **MultipeerConnectivity**: inputs-only
      sync, one peer as clock host, join/leave flow
- [ ] Cross-device play (iPhone/iPad/Mac in one room), no server
- [ ] Local network privacy strings + Bonjour service declarations
- [ ] Stretch: scale beyond 4 players (lockstep makes it reachable)
- [ ] **Decide pause semantics for networked play.** The couch map-tap pause
      freezes one device; under lockstep that's a whole different problem
      (whose tap freezes everyone? re-sync on resume?). Likely: no free pause
      in a networked race (or a vote/host-only pause). Decide here, not in the
      couch code.

## The real game — UI redesign, profiles, records, tournaments

**The gap this fills.** Everything so far has been built to answer technical
questions — is the drift fun, can a phone build a track, does a bridge work — and
the surface around it is scaffolding put there to reach those answers. Two things
are missing, and they're the same thing from different ends: the game keeps no
record of what you did, and the app has no shape beyond "start a race".

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

Then the game layer proper. The pieces are closer than they look — per-track
personal bests and full ghost recordings already persist, keyed by track id — but
nothing above them ties results to *people* or to a series. Ordered so each step
is useful on its own:

- [ ] **Local player profiles.** A chosen name at minimum, on-device only (no
      accounts, no server — see "out of scope"). Everything below hangs off
      this, which is why it's first. Open question: allow ad-hoc anonymous
      players, or make everyone pick a name up front?
- [ ] **Records that stick, and are worth looking at.** Best lap and best race
      already persist per track; make them visible and per-profile — a results
      screen worth reading, "you beat your best" in the moment, and a per-track
      board of who on this device holds what.
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

## The store release — *this one is 1.0 by definition*

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
      v0.5). App name is settled: **Skid Jam**.
- [ ] One ASC record (Universal Purchase), listing text + screenshots,
      privacy questionnaire (nothing collected)
- [ ] Submit, await review, release (release lane already live since
      v0.5)

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
