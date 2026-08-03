# Roadmap

The implementation plan, in milestone order. Versions are indicative, not
contractual, and this file is *expected to churn* — milestones get reshaped as
prototyping answers questions. Everything before 1.0 is beta by definition
(TestFlight from v0.1). As milestones ship, they drop to the
[README version history](README.md#version-history) (brief) and
[CHANGELOG.md](CHANGELOG.md) (full), and this file keeps only open work.
Settled rules, conventions, and design decisions live in
[AGENTS.md](AGENTS.md); this file is only *when*, not *why*.

Guiding order: **the drift is the game.** Milestone one exists to answer "is
the driving fun?" and nothing that doesn't serve that question lands before it
is answered. Multiplayer-on-one-device is the product's heart, so it comes
right after the driving is proven; networking is deliberately last among the
features because deterministic lockstep is designed in from the first line of
the sim, not bolted on.

What that order leaves for late is the game *around* the race, and the app around
that. Today a result evaporates the moment it ends, and the UI is a harness built
to reach the technology rather than a design. **v0.9.0 is both** — the real front
end plus profiles, records and tournaments — deliberately after the technical
foundation (editor, platforms, networking), since a menu redesign wants to know
what it's presenting and shared times lean on identity and transport decisions
those milestones settle.

---

Shipped milestones (v0.1–v0.5) are summarized in the
[README version history](README.md#version-history); full detail is in
[CHANGELOG.md](CHANGELOG.md). This file keeps only open work.

## v0.6.0 — Track editor & shareable tracks

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

- [ ] **Height readout on the map.** A tiny label on each piece showing its
      height, behind a show/hide toggle — building in three dimensions from a
      top-down view means the numbers are otherwise only inferable from shading.

## v0.7.0 — Platforms & input

The game only runs one way on one kind of device: portrait, on a phone, driven
by thumbs on glass. This milestone is about the OTHER ways in, and it sits here
because networking (v0.8) wants the input and orientation questions settled
first — a Mac joining a couch race needs a keyboard scheme to exist, and a
locked orientation is one less thing to synchronise.

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

## v0.8.0 — Local-network multiplayer

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

## v0.9.0 — The actual game: UI redesign, profiles, records, tournaments

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
      a product — a real front end, a track browser (needs the library from v0.6),
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
      v0.8 means the track-identity and transport questions are already answered.
- [ ] **Career ladder** with cosmetic-only unlocks (liveries, effects) to show
      off when racing others — never performance. Wants profiles and tournaments
      under it first.

## v1.0.0 — The store release

- [ ] **Final polish & balancing pass.** With all content and controls
      settled, do the tuning that only makes sense at the end: **bake the
      final control-feel dials** (the aim-drift model + defaults shipped in
      v0.5; the live dials let this wait), **balance** the tracks / AI /
      difficulty, and sweep the remaining rough edges. This is why the
      control-feel tune was deferred here.
- [ ] Icon polish pass (light/dark/tinted variants — the base icon ships with
      v0.5). App name is settled: **Skid Jam**.
- [ ] One ASC record (Universal Purchase), listing text + screenshots,
      privacy questionnaire (nothing collected)
- [ ] Submit, await review, release (release lane already live since
      v0.5)

## Backlog (unversioned)

- [ ] **Map themes**: whole-map looks beyond grass (sand/desert, snow, …).
      The track format already carries a `theme` field; the renderer learns
      it when the first non-grass theme lands.
- [ ] Full replay viewer (watch/scrub any stored run — the data exists from
      v0.2). Sharing a run as a ghost is in v0.6.5.
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
      devices at once. Now that profiles land *after* networked play (v0.9 after
      v0.8), revisit it there — if your device is your identity on the network,
      this may be moot.

## Deliberately out of scope

Per [AGENTS.md](AGENTS.md): no ads, no IAP, no accounts, no server, no global
leaderboards, no third-party runtime dependencies. Networked play is
peer-to-peer on the local network only. watchOS/visionOS/tvOS not targeted.
No performance tuning or upgrades — cosmetic unlocks only (see AGENTS.md for
the why).
