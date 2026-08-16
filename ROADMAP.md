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
**the front end blocks more than it looks like.** Color picking, profiles,
records and a track browser all need surfaces that do not exist yet, so they queue
behind one redesign rather than being four independent tasks.

---

Shipped milestones (v0.1–v0.7) are summarized in the
[README version history](README.md#version-history); full detail is in
[CHANGELOG.md](CHANGELOG.md). This file keeps only open work.

## Release grouping

Rough, and expected to churn — the point is which themes are worth shipping
*together*, not what they will be numbered.

| next | then | later | 1.0 | parked |
| --- | --- | --- | --- | --- |
| The front end | Tournaments & sharing | More to build with | Polish & submission | Surfaces & hazards |
| Identity & records | Networked play: the tail | Platforms & input | | Car color |
| First ten seconds | | | | |

The **track library** sits inside *Tournaments & sharing* but depends on nothing —
it is design work, not code, and can start at any time. It gates tournaments.

**Why that order — and it changed.** The racing works; the *game* around it is
undesigned, and the front end is where that gets decided rather than merely drawn.
A menu cannot be built without answering what a player picks, in what order, and
what survives between sessions — and those answers are the game. So identity and
the menu come first, tournaments follow (the only genuinely new mode, and the one
that gives a five-second lap a reason to be driven forty times), and the structure
is set out in [docs/game-shape-plan.md](docs/game-shape-plan.md).

**Surfaces moved back**, having been *next* on the strength of "the sim half is
already done" — true, and not a reason to build it. A lap is 5–10 seconds on a
track the player can see all of and will drive forty times, so surface variety is
a change every second or so with nothing to learn about it; authoring is 47
decisions on the clover. A whole-track surface as part of a *theme* may still earn
its place as a look, which is a much smaller feature than the per-piece one.

## Surfaces & hazards — *PARKED*

**Parked until the game is more finished.** Everything in this section — hazards,
per-piece road surface, off-road surface, themes — is on hold, and the roadmap says
so rather than leaving it looking live.

The pattern worth naming, because it caught the same feature twice: each of these
is **cheap to build and unproven to matter**, and "the sim half is already done"
kept being read as a reason to do it. That is a statement about cost. On value: a
lap is 2741–5141 units, so **5–10 seconds**, on a track the player can see all of
and will drive forty times — surface variety at that scale is a change every second
or so with nothing to learn about it, and the clover's 47 pieces make it 47
authoring decisions per track.

**One exception survives, and it belongs to the library rather than here:** *some*
decoration before 1.0, so that a dozen tracks do not all read as the same asphalt
ribbon on the same green. That is about tracks having character, not about how they
drive — scope it that way, and it needs none of the parked work above. See
[docs/game-shape-plan.md](docs/game-shape-plan.md).

What is missing, if any of this is ever built: **placement and the look of a
boundary**.

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
      with it (ground color, grass texture), so it ships alongside decorations —
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

- [ ] **Choose your color in the lobby**, from the measured accessible nine,
      with the default assignment being the accessible set (see
      [docs/first-glance-plan.md](docs/first-glance-plan.md) — the palette work is
      done, the picker is not). Under networking a color must be agreed centrally,
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

The *palette* half **shipped** with the nine-car grid, the **white sheen** that was
quietly undoing it is now gone, and a **reversing mark** says when a car is
traveling backwards rather than merely pointing that way. What remains:

- [ ] **Bring back the headlight cone — as an occlusion query, not a decal.**
      Wanted back: it made facing unmistakable, and a **night track** with brighter
      cones is a look worth building toward.

      **Now the main facing cue, not a nicety.** With the sheen gone and two-tone
      ruled out at nine cars, facing rests on the nose lamps and the tucked-back
      cockpit — deliberately weak marks. The cone is also the *only* facing cue that
      costs nothing from the color budget, because a thrown beam adds no color to
      the car's body; every on-body cue competes with telling the cars apart.

      Parked until the design is right, and two attempts are already spent, so start
      from these:
      - **Clipping the cone to its own storey's road was tried and rejected** — the
        clipping itself is distracting. Do not re-propose it.
      - It must **not shine through walls**, and must **cross storeys** without
        being sliced at a ramp foot.

      The root bug is layering an *extended* thing by its origin's storey: a car is
      a point so single-storey binning is fine, a 60-unit beam is not. So the cone
      wants a lit-surface query — which road and wall geometry the beam actually
      reaches — the same shape as the covering-deck scan that already drives the
      under-deck window in `TrackRenderer+Cars`.

- [ ] **Pick your own color.** Decided: duplicates prevented by **first-come
      claiming** in the lobby rather than a rule about taste, and local-vs-remote
      marked with a **ring or seat number** — not desaturation, which is measured to
      wreck the palette (worst pair 24.7 → 6.5 at 55%). Waits on the front end.

      **Two-tone belongs here, and its cost is now measured.** A second body color
      only works if it is a genuinely distinct hue — a light/dark shade of the base
      was tried and reverted, because the comparison that matters is *any patch of
      one car against any patch of another*, and that fell to ΔE 4.6 (against 24.7
      for one tone, and the old sheen's 3.7).

      The budget is **tones, not cars**. Two hues per car needs 2N mutually-distinct
      tones, and nine is already the edge of what color-blind-safe lightness spread
      allows — so measured from the current palette: **4 cars two-toned is fine
      (26.3), 9 is impossible.** That makes it a picker feature, where the field size
      can bound which pairs stay selectable, rather than arithmetic in the renderer.
      `CarLiveryRenderTests.testCarsStayDistinctAcrossEveryToneTheyWear` has the
      one-line hook to extend and will hold whatever lands to the same floor.

- [ ] **Two more, both small.**
      - **Which car is mine, on the grid.** A number bubble and a ring during the
        countdown, the number **rotated to face its own player** — the rig already
        knows that vector (`ZoneChrome.up`), and `Race.Phase.countdown` already
        exists to hang it on.
      - **The control pad should be visible before it is touched.** `origin` is nil
        until touch-down today, so the control appears only once you already know
        where to press. Give it a dimmed resting position at the center of its own
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
      own behavior.

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

      Left: **step 7, the chrome** — and it has grown from "where does the closure
      control land" into a real pass, now that the editor has been used on device.
      Reported, in the author's own order of annoyance:

      - **The chrome covers the track.** Buttons overlap the map by default, on a
        screen where the map is already the smallest it will ever be. Nothing else
        here matters as much: the thing being edited is partly hidden.
      - **The button organization is arbitrary and takes too much space.** Trash,
        undo, redo, fit, copy, shelf, levels, gates, palette, radius and pitch are
        all present at once, grouped by how they were added rather than by what
        they are.
      - **Modes are invisible.** Gate mode, rail-new-pieces and the level filter are
        modes, but nothing says so at a glance — you cannot tell which are on, or
        that they are the kind of thing that stays on.
      - **Rails have TWO controls for one idea**: a sticky "rail new pieces" toggle
        in the palette, and a per-piece checkbox in the properties sheet. Both are
        defensible alone; together they are confusing, and they do not look alike.

      The organizing question is one word per control: is it an **action** (do it
      now), a **mode** (stays on until turned off), or a **property** (of the track,
      or of the selected piece)? The rail pair is the clearest case of that
      distinction being unmade.

      Two things that already have homes and set the pattern: track-wide settings
      live in the properties sheet behind the name chip (`TrackPropertiesSheet`),
      and the retro pass reached most of the editor but **missed these controls** —
      the rail toggles and the piece-properties rows are still rounded and native.

      Still explicitly a decide-on-device step.
- [ ] **The editor can only open ONE track.** The library already stores many —
      `TrackLibraryBook` keeps names, dates, signatures and an `isRaceable` flag — but
      `editorLayout` is a single buffer restored from a single slot, so every entry is
      raceable and only one is ever editable. Edits already flow *to* the library;
      nothing flows back.

      **The hazard is in-place mutation.** `syncEditedTrackToLibrary` rewrites the
      edited entry on every change, so "open track X" would silently overwrite X.
      That makes two distinct acts, and both are wanted: **edit this track**
      (continue my own work) and **start from this track** (a copy, so the original
      survives — which is what opening a built-in must do).

      *"Scratchpads" need no new storage:* an unfinished track is already an entry
      with `isRaceable == false`, kept by the library and withheld from the picker.
      What is missing is seeing and opening them — a list, plus new / duplicate /
      rename / delete. This is the **track browser**, and where previews earn their
      place: a list of names says nothing, a list of thumbnails is the feature.

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
several other features: a color picker, a profile, a records screen and a track
browser all need surfaces that do not exist. That is why they are one milestone
rather than four.

**And it is where the game gets designed, not just drawn.** A menu cannot be built
without deciding what a player picks and in what order, so this milestone is
carrying the questions the prototype never had to answer: solo vs couch vs nearby
as a *choice* rather than a player-count stepper, which modes exist, and what
survives between sessions. The structure — including the case for local profiles
first and the open tournament rules — is in
[docs/game-shape-plan.md](docs/game-shape-plan.md). Two facts from that survey,
because they size the job: the setup screen is **351 lines with every knob flat on
it**, and of 28 persisted settings **25 are developer tuning dials**.

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

- [x] **Local player profiles — and guests, which are the default.** SHIPPED. A
      profile is a chosen name and color, on-device only.

      **Decided: guests, not name-up-front.** A seat races immediately with no name
      and no setup. Asking for a name first would put a text field in front of the
      thing people opened the app for, and a couch guest who wants one turn should
      not have to register for it.

      **And a profile stays exactly that — a name and a color.** It is a label for a
      seat, not an account: it cannot travel between devices (nearby play identifies
      people by device), and the phone belongs to somebody, perhaps shared with kids.
      Anything that treats it as an identity to hang a data model off is building for
      a situation this app does not have.
- [x] **Records that stick, and are worth looking at.** SHIPPED, across four PRs:
      past laps in the trial, "you beat your best" in the moment, attribution, and a
      board per track.

      **Time trial now shows your past laps**, not only the best one — a windowed list
      of recent laps with the fastest starred, and that time pinned once its lap has
      scrolled away.

      **"You beat your best" now lands**, and deliberately differently per mode, because
      the modes differ: a trial has no ending, so a new record is crowned in the lap list
      as it happens, quietly; a race has one, so its results screen names what fell and
      the time it beat. The signal comes from the write itself — the book only holds the
      *current* best, so "was that a record?" has to be captured as the record is set.

      **Both shipped.** Times are attributed (the holder's NAME, not their profile id —
      a record is a snapshot, so deleting or renaming a profile must not rewrite who
      drove it), and the track picker doubles as the board: every track shows its best
      lap and whose it is, or "No time yet".

      **Records stay per TRACK, not per profile** — a plan that was written and then
      argued out of. On a device that belongs to one person (perhaps shared with
      kids), a second record book per name mostly *fragments* the owner's own board
      the first time somebody else plays. And a profile cannot travel, so there is no
      wider board for it to feed.

      What is worth having instead is **attribution**: store who set a time alongside
      it, so a board reads "best lap 0:42.1 — Ada" without a second axis of storage.
      A guest's time is stored with no name, which is honest rather than a hole.

      Per-profile record books stay possible if kids sharing a phone each want their
      own best to chase — but that is a "when it comes up" feature, and attribution
      does not block it.

      **A record is a SOLO time, and a nearby race sets none.** Already true —
      `noteProgress` requires one local player, stock physics and normal pace — but
      worth stating, because "should remote players set records on my device?" is a
      question that will come back. Two reasons, and the first is mechanical:

      - **A client is not simulating.** Networked play is host-authoritative, so a
        guest's device renders snapshots rather than stepping its own race. A time it
        showed is a number the host sent, not something it can reproduce — and a
        record's ghost is a lap of *inputs replayed locally*, which a client does not
        have; it has a stream of positions. The host is the exception on this point,
        since its device does run the sim.
      - **A lap in traffic is not the same lap.** Contact, slipstream and being held
        up make a race lap incomparable with a time trial, which is what a board is
        for. This one catches the host too.

      **The ghost storage is fixed** (was: 1.2 MB on a test device, and multiplying by
      profile once records are per-player). A stored ghost is now **one lap, packed at four
      bytes a tick**: 138 KB → 5.2 KB on a 3-lap clover, 446 KB → 5.2 KB on a 10-lap one —
      constant whatever the race length, which matters once lap count is a setting.

      That also settled the question of whether every track keeps a ghost forever: at 5 KB
      each, yes.


## Tournaments & sharing — *a reason to keep playing*

- [ ] **Make the track library a channel, not a fixed set.** The dependency nobody
      scheduled, and the one that decides whether tournaments feel good: **a series
      is only as good as the tracks it draws from**, and four built-ins means every
      five-race series repeats itself, which no scoring rule fixes.

      **Sharing is the leverage.** Hand-authoring is the floor — six to eight
      built-ins, because a tournament needs a pool present on first launch — but
      every hand-made track costs a design session *and an app release*. A track
      that travels as a link or a QR code can come from the site, a friend, or a
      player, with no app update. Plan:
      [docs/track-sharing-plan.md](docs/track-sharing-plan.md).

      The whole track rides in the link (`skid.misaki.fi/t/<code>`), so nothing needs
      a server and a link cannot rot; the path form matches the AASA already
      deployed. Previews are needed in the app anyway — the library list wants
      thumbnails, the share screen wants a picture — and `EditorRenderer.drawTrack`
      already draws a layout at any scale. A curated collection on the site is static
      content, with images produced by running that renderer. **Anyone else may host
      their own collection**; the design privileges no domain.

      The hand-authored floor is still authorship, not engineering: the catalog
      already offers three straights, 45°/90° curves at three radii each, hairpins,
      fitters, elevation, crossings and railings, and four tracks have been designed
      with all of it. Aim for a deliberate spread — short/technical through
      long/fast, a couple that climb.
- [ ] **Tournaments.** A series of races across one or more couch sessions, with
      standings per profile. Also *unlocks* the **reverse-standings grid** (race
      N starts in reverse order of the standings after N−1, worst on pole; ties
      broken by the seeded RNG), which is blocked today purely for lack of a
      cross-race standings layer.
      Open, with a leaning each: length (3/5/7, tracks drawn from the library with a
      re-draw before starting); **points rather than cumulative time**, so one bad
      race does not end the series for a couch; and it **must survive quitting**, or
      a five-race series on a phone is unfinishable. Needs the library item above
      first. See [docs/game-shape-plan.md](docs/game-shape-plan.md).
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
      only render/input capture differ. `SkidKit` already declares `.macOS(.v14)`
      and neither renderer imports UIKit, so this is less than it looks.
      **Also unlocks the track-preview generator**: a Mac build links the renderer
      already, so rendering a code to a PNG becomes a render mode on that target
      rather than a second executable — see
      [docs/track-sharing-plan.md](docs/track-sharing-plan.md).
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

      **Past nine is a per-track question, and the code is nearly ready for it.**
      `StartGrid.rows(for:)` and `positions(count:)` already lay out any count, so
      `Grid.slots = 9` and the start piece's depth are what actually bind — a bigger
      grid means a longer start piece, which makes capacity a property of the track
      rather than the app. Deliberately not ruled out; the rules for choosing a track
      and a field size belong with the later game-building work, and the palette
      would need extending past nine to match.
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
