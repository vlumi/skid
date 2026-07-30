# Changelog

All notable changes to Skid are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Grouped by **marketing version** (a roadmap milestone), then by **build
number** within it — the version stays steady while the build climbs each
TestFlight upload (see [RELEASING.md](RELEASING.md)). The build heading is
just `### build N — <date>`; the version comes from the `## vX.Y.Z` above it.

Each version's top section, **Unreleased (next build)**, collects entries
merged to `main` but not yet in a TestFlight build; cutting a release renames
it to that build's heading and opens a fresh empty one. Keep that heading
immediately followed by its list items (no prose between), so the release
script can promote it with a one-line edit. A user-facing PR writes its own
bullet here; the `## vX.Y.Z` marketing heading is hand-set when a milestone
ships (see [AGENTS.md](AGENTS.md)).

## v0.6.0

### Unreleased (next build)

- **Pieces near other roads are no longer refused when nothing touches.** The
  overlap check measured distance between road CENTERLINES, which overstates
  wildly when a piece merely ends near another road — a rising curve with a
  third of a road width of clear grass was refused as an overlap. It now
  measures the asphalt itself.
- **Roads can cross at ground level.** A track can now run across itself
  without a bridge, so a figure-eight works flat — build one road, then take
  another straight across it. Roads that merely graze each other at a shallow
  angle are still refused, since that is nearly always a mistake rather than a
  junction.
- **Checkpoints are edited in their own mode.** A tap on the track used to mean
  two things at once — pick the end you're building from, or add a checkpoint —
  so it was easy to move a checkpoint you never meant to touch. Tap **Gates** to
  switch: checkpoints stand out, every seam that can take one is marked, and
  taps do nothing else until you're done.
- **Undo and redo in the track editor.** Every edit can be taken back —
  placing pieces, deleting, gating, rotating the whole track, raising and
  lowering it — with a long history, so a wrong turn thirty pieces ago is
  still recoverable. A one-tap compound counts as one step, and the delete
  button now wears a bin rather than an undo arrow.

### build 10 — 2026-07-29

- **A track can close even when the pieces don't quite meet.** Mixing straights
  along the grid with diagonal ones used to leave gaps no piece could fill, which
  made some shapes — a figure-eight with one diagonal loop, say — impossible to
  finish. When that happens the editor now offers to close the loop with a fitted
  piece, shaped to the gap.
- **The app icon's car matches the one you drive.** Same lit nose and
  rear-seated driver as in the game, instead of the older plain body.
- **Railings stop you where they look like they should.** Coming off the grass
  at a ramp or bridge, the car used to stop just short of the railing, in
  mid-air. A railing is now exactly as solid as it looks, at every height.

### build 9 — 2026-07-28

- **The road on a bridge is as wide as it looks.** An elevated road is drawn
  wider than one on the ground, but the game still used the ground width — so
  a strip of the bridge that looked like asphalt behaved like grass, and you
  could fall off a deck you were still driving on.
- **Race positions follow the road.** Live standings measured "who's closer
  to the next checkpoint" as the crow flies, so on a track that curls back on
  itself a trailing car could rank ahead of the leader rounding a loop —
  progress is measured along the road now.
- **No hairline gaps in the race view.** The seam overlap that keeps piece
  joints solid held in the editor but shrank under the race map's scale;
  walls showed it first.
- **See through bridges.** A car driving under a deck now shows through a
  dark window in the road above — the car itself, pointing where it points,
  instead of the solid colored dot. The hole covers the bridge's whole width,
  railings included, and a car driving ON the deck passes over it.
- **The car shows where it points, without the headlight beam.** The thrown
  cone kept landing on the wrong surface around ramps and bridges, so the
  body carries the cue now: a lit nose, and the driver seated at the back
  like the classic single-seaters.
- **Steering works with your thumb near the screen edge.** On phones with a
  notch, a thumb that strayed into the inset used to leave the stick barely
  able to turn — it now points where your thumb is, at full lock.
- **No more hairlines between track pieces.** Abutting pieces overlap enough to
  cover the edge blending now — most visible on a ramp, where the seam ran
  through a gradient.
- **Cars and bridges stack correctly, everywhere.** A car that slid onto the
  grass under a bridge used to be drawn on top of it. The world is now painted
  strictly bottom-up — ground, then whatever stands on it, then the level above
  — so what covers what follows from where things are, not from a list of
  special cases.

### build 8 — 2026-07-27

- **A rebuilt editor palette.** Picking a piece used to mean tabs, a radius row,
  and ten buttons that multiplied with every family added to the catalog. Now
  it's turn left, turn right and go straight, with how-tight and uphill/downhill
  as small three-way pickers beside them — everything visible, one tap each.
- **A new built-in: Clover.** Four sweeping loops that cross themselves at two
  heights, and the first track whose start line sits up on the deck — the lap
  dips down to ground level and climbs back.
- **Raise and lower a whole track.** New controls above the palette turn the
  track either way and lift or drop it half a level at a time — so a start line
  can sit up on the deck, and a bridge can cross under itself. The height
  buttons gray out when there's no room left to move.
- **A smoother Eight.** The built-in figure-eight was rebuilt in the editor
  with the new pitch tools — gentle sweeping climbs instead of straight ramps.
- **Skid marks on bridges.** Rubber, mud and scuffs now print at every height,
  each drawn on its own level — deck marks on the deck, ground marks under it.
- **Gate taps land where you aim.** Tapping to set a checkpoint used to need
  the piece before the seam you meant; now the tap targets the seam itself.
- **Lay road uphill and downhill.** A pitch selector (up / level / down)
  joins the palette: every straight and corner can climb or descend half a
  level, so ramps stop being a special button — build a bridge from any shape,
  at any radius, pause a climb halfway, and put a checkpoint at its apex. The
  under-bridge rules follow automatically: embankments seal, decks stay open.
- **Build any shape from the same few pieces.** Corners are 45°, so two make a
  90° and four make a hairpin — which means you can put a checkpoint at a
  hairpin's apex, or anywhere else you like, instead of only where a big
  prefabricated piece happened to end. Share codes stay just as short: they pack
  runs of corners back down as they're written.
- **A tidier editor.** Delete and Close-the-loop moved onto the map, right at the
  end you're building from, and the top bar is all icons — so the track gets the
  space the buttons used to take.
- **The editor stays quick as the track grows.** Placement checks and the
  close-the-loop suggestion used to re-measure the whole track against itself on
  every tap, which dragged once a design ran long; they now share one indexed
  proximity rule, so a forty-piece track edits as smoothly as a four-piece one.
- **Track codes from earlier builds no longer load.** Checkpoints are numbered
  against the new smaller pieces, so an older code would come back the wrong
  shape. Copy your track out of the editor again to get a fresh code. (The
  built-in tracks are unchanged to drive — same corners, same start line.)
- **Laps count properly on Big oval.** The track had two checkpoints stacked on
  the start/finish line, so after the first lap the finish had to be crossed
  twice before the lap registered. Checkpoint numbering is now uniform — each one
  marks the end of a piece — so no two can land on the same spot. The start line
  and grid are exactly where they were.

### build 7 — 2026-07-26

- **Build your own tracks.** A new track editor lets you lay a course piece by
  piece from the start line — straights, curves, hairpins, and ramps — extending
  from a loose end until the loop closes back on itself. The layout renders live
  as you build, with a "build here" arrow on the end you're extending and
  construction stripes on any end still open. Tap a joint to mark a checkpoint,
  and when the loop closes you can race it. A "My track" slot keeps your design
  between sessions, and Copy/Paste moves a track around as a short share code.
  The editor shows the size limit as a dashed boundary, and a Rotate button turns
  the whole track 45° at a time to reshape its footprint.
- **Every track is built from the same pieces, including the built-in ones.**
  Small track, Big oval, and Eight replace the four hand-authored circuits, and
  they're made of exactly what the editor gives you — so a built-in can be
  opened, reshaped and raced like your own. What you build is also literally what
  you drive: the editor and the race draw from the same pieces with the same
  renderer, so kerbs, rails, markings and shading match. (Surface hazards like
  the old oil patches will return as a piece you can place.)
- **Roads that look like roads.** Every road carries a thin white edge line, and
  corners earn red/white kerbs where a real circuit puts them: at the apex you
  cut, on the outside of a corner exit where you run wide under power, and on
  both sides of a chicane. Kerbs are worked out from the whole layout's corners
  rather than piece by piece, so one continuous kerb runs across several pieces
  with an even stripe rhythm — and all of it sits outboard, so nothing narrows
  the road you actually drive on.
- **Bridges you can drive.** Elevation is one continuous height from ground to
  deck: the car climbs a ramp, rides the deck, and comes back down in one smooth
  motion, widening the road and growing the car as it rises. A bridge crosses
  over its own road, so cars above and below pass each other cleanly, and the
  deck and its ramps are fenced. Ramps are for driving up — for being launched,
  there's the jump piece. One "Deck scale" dial in the Tuning panel tunes the
  whole elevated look at once.
- **A debug overlay.** Tuning → Debug → "Show sim overlay" draws what the
  simulation believes on top of what you see: the centerline colored by height
  (green at ground, red at deck), every wall with its height, and each car's
  height, surface and on-road state.

## v0.5.0

### build 6 — 2026-07-24

- **Each player picks their own controls.** Casual (aim) or Pro (d-pad) is
  now chosen per player in setup, under their color — so one couch can mix
  aim drivers and d-pad drivers. (The old global scheme toggle in the pause
  menu is gone; set it before the race for now.)
- **Everyone ready? Tap to go.** A race now opens frozen with a Play button
  on the map — get all your thumbs in place, then tap the map to start the
  countdown. No more scrambling because the race began before you were set.
- **Tap the map to pause.** The pause button is gone; once the race is
  running, a tap on the map opens the pause menu (the same map tap you used
  to start). The track stays clear of any button, on every seating.
- **Your position, right in your chip.** Each player's chip now shows their
  live race position (1st, 2nd, …) next to the lap counter, so you always know
  where you stand without a shared scoreboard. It settles briefly before
  changing, so a photo-finish for a spot doesn't flicker the number.
- **A clear finish, with your splits.** When you take the flag, your lap
  times appear right in your control band — an unmistakable "you're done,
  here's how it went" instead of guessing whether the race is over.
- **Pro's pad stays put.** The direct steer/throttle pad now anchors where
  your thumb first lands instead of trailing it — so gas / brake / left /
  right keep fixed spots. Holding the gas no longer creeps the pad up the
  screen. (The Casual aim stick still trails your thumb, which suits
  constant re-aiming.)

### build 5 — 2026-07-23

- **The grid's shuffled every race.** Who starts on pole is random now, so
  no one's stuck with the same start over and over. Still fully
  deterministic under the hood (replays and ghosts are unaffected).
- **The track's clear of your thumbs now.** On a shared screen each player's
  controls live in a band in the grass beside the map — below the map from
  their seat (rotated for players across the table) — instead of over the
  whole half/quadrant. The track sits clean in the middle: no more zone
  outlines or fingers covering the road, and lap/time chips ride the outer
  edge of each band, out of the notch. One shared pause sits on the seam
  below the map. The map and every control center within the safe area on
  notched phones — only the band's tinted box bleeds to the screen edge.
- **The stick follows your thumb to the edge.** Drag past the edge of the
  control stick and it slides along with your finger instead of pinning —
  so in a narrow control zone you can swing full-left to full-right without
  lifting off. Works for both Casual (aim) and Pro (d-pad).
- **Two control schemes, named.** The prototype roster is down to the two
  that earned it: **Casual** (aim where you want to go, the game handles the
  drift) and **Pro** (direct steer + throttle, now drifting too). Slide,
  two-zone, one-touch, and split are gone — on a touchscreen they never
  beat these two.
- **The d-pad drifts too now.** Hold a direction at speed and the body
  flips into the corner like the aim scheme does — no delicate countersteer
  to hold a slide. A light thumb still places the car precisely (the assist
  scales with how far you push), so analog fine control is intact; it's the
  full-lock holds (and the keyboard later) that get the drift. Tune it with
  the new "Flip" dial in the pause menu. The flip now stays gentle at low
  speed and only really bites once you're moving (for aim mode too), so
  slow maneuvering isn't twitchy.
- **A "Grip" dial** for the drift's weight: turn it down and the car's
  motion lags where it's pointing longer — a heavier, slidier feel — up and
  it snaps to the nose. Plus the aim "Flip rate" now dials all the way to 0
  for the light-touch end.

### build 4 — 2026-07-23

- **Aim-to-drive now drifts like it means it.** Point off your nose at
  speed and the car's **body flips toward the aim almost instantly** — the
  faster you're going, the harder it whips around (handbrake inertia) —
  while your momentum carries and catches up gradually. Stay a little
  ahead of the corner and you hold a clean drift all the way around. And
  drifting no longer costs speed: the slide **redirects** your momentum
  along the nose instead of scrubbing it (it never adds any — top speed is
  top speed). Reversing still works where it should: point behind you at
  crawling speed to back up.
- **A tuning playground for the drift**: flip rate, speed boost, drift
  keep, reverse threshold, gas ease, and the classic schemes' turn rate —
  all live dials in the pause menu's Tuning panel (physics dials apply on
  Reset; hiscores only count on the stock setup, like Pace).
- **The heading arrow moved out where you can see it** — a bold arrow
  floating ahead of your car in your color, instead of a tiny dart glued
  to the nose of an already-tiny car.
- Old personal bests and their ghosts were set under the old physics, so
  they won't match the new feel — new bests await.

### build 3 — 2026-07-22

- **Aim-to-drive**, a new control scheme in the switcher: a floating stick
  like the d-pad, but you just point where you want to go — the car turns
  toward it at a natural pace and backs up when you point behind it. No
  separate gas and brake to juggle. The d-pad and the other schemes are
  all still there to A/B against.
- **Smoother corners on every track**: curves now bake at a fine, even
  resolution, and the previously sharp chicane and figure-eight joins
  flow instead of kinking — most visible on the Overpass's diagonals and
  the Hairpin's tip. Under the hood, every track is now *data* (a design
    of corner nodes the game compiles), the groundwork for a track editor.
- **Friendlier controls, same skill ceiling**: the wheel now eases toward
  your thumb instead of snapping, so a twitch no longer jerks the nose —
  full lock is still just as quick to reach. Analog steering with a gentle
  response curve is the new default (the on-thumb favorite); the Tuning
  panel still lets you dial it back.
- **A heading dart** ahead of each car's nose, in its color, so you can
  see where you're actually pointing mid-drift — when the car is sliding
  sideways, the nose and the travel direction part ways.
- **Overpass, less brutal up top**: the bridge deck now has retaining
  rails down its middle (only up on the deck — the road underneath passes
  clean through), so reaching the mid-bridge checkpoint isn't a tightrope.
  The ramp walls line up with the deck edge and no longer jut into the
  road running beneath, and you can't clip onto the deck from the wrong
  side any more.
- **Hairpin actually has to be driven**: its apex checkpoint sits across
  the tip now, so cutting straight across the neck to the return lane no
  longer counts — you have to round the far end.
- **The pause button has a home**: every track now has a "pit" — an
  infield spot near the start/finish — and the pause button lives there,
  always off the racing line instead of pinned to screen-center (where it
  sometimes sat right on the road).

### build 2 — 2026-07-22

- A **Tuning** panel in the pause menu, for finding the feel on real
  thumbs: d-pad dead zone, travel, steps (including full analog), and a
  response **curve** (softer near the center for smoother small
  corrections) — all applied live mid-race — plus a **Pace** dial that
  slows acceleration and top speed for learning (agility stays; applies
  on Reset, and slowed runs never touch your hiscores). All remembered
  across launches.
- **Sound**, all synthesized live (no audio files, like the graphics):
  an engine note that climbs with your speed, tire noise when you slide,
  and thumps when you hit walls or each other. Respects the silent
  switch and mixes politely with your own music.
- **Haptics**: taps for impacts (harder hit, harder tap) and a success
  buzz when you take the flag.
- Sound and haptics toggles in the pause menu, remembered across
  launches.

- **Overpass** — the figure-eight, and the two-layer system it rides on:
  yellow-striped ramps lift you onto a **bridge** over the crossing (with
  its own checkpoint — the overpass must be driven, not dodged), stray
  off the edge and you drop back down. Cars under the bridge show
  through as a colored bubble so nobody ever loses their car. Jump
  ramps (full ballistic flight, no steering mid-air) are in the engine,
  waiting for a track that dares to use them.

- **Two new tracks**, picked on the setup screen: **Gauntlet** — the
  rectangle pinched on both straights, narrower road, mud filling the
  bottom chicane — and **Hairpin** — a fast bowl feeding a tight 180°
  peninsula with its own checkpoint at the apex. Hiscores, ghosts, and
  time trial are all per-track. Every built-in track has to prove an AI
  can lap it before it ships.

- Race chrome that stays out of the way: each player's lap/time chip now
  lives in their **own corner, facing them** (rotated for players across
  the table), the countdown shows both ways in face-to-face games, and
  the in-race buttons are gone — one small **pause** button on the center
  seam opens a menu (resume / scheme / reset / setup) and actually
  freezes the race. System edge swipes now need the deliberate
  double-swipe, so a thumb at the edge doesn't summon Control Center
  mid-corner.

- **AI drivers**: fill the grid with up to 3 opponents from the setup
  screen. They drive the same cars with the same physics (no
  rubber-banding — a skill ladder of lookahead/caution instead), follow
  the racing line, drift the corners, and recover when they hit a wall.
- **Time trial**: lap forever against the clock — live lap timer,
  session best, and your all-time **best lap** and **best race** are now
  saved per track (survives relaunch). The best race also stores its
  full replay…
- **Personal-best ghost**: …which drives alongside you in time trial as
  a translucent ghost car — race your own record. Never collides, never
  leaves marks.
- **Seating options**: 2-player picks side-by-side or face-to-face;
  3-player picks which corner of the screen stays open — controls always
  face the player.

- **Couch multiplayer**: 2–4 players on one device, one thumb each. A
  setup screen picks player count, per-player car colors (tap to cycle),
  and **Contact** (cars bump — derby chaos) vs **Ghost** (pass through —
  pure speed) before each race. Every player gets their own control zone
  (halves for two, quadrants for four — the top row's controls face
  players sitting across the table), outlined in their color; touches
  are routed by where they start, so thumbs never steal each other's
  cars. Per-player lap chips in the HUD, next-checkpoint dots per player,
  and a results card with standings and best laps when everyone's done.
- New **Split** two-thumb scheme in the switcher: one thumb gas/brake,
  the other steer, both in quantized steps.

- Checkpoints you can see and can't unfairly miss: gates now span the
  whole corridor (running wide over grass still counts — the grass is the
  penalty), only gross cuts through the infield don't. Each checkpoint is
  drawn like a physical gate — a faint line with a post at each road edge —
  and a dot in **your car's color** lights up beside your next gate's
  posts (each player gets their own dots); the start/finish keeps its
  checkers.
- It's a race now: three laps against the clock — 3-2-1-GO countdown
  holding the car on the grid, lap counting through ordered directional
  checkpoints (cutting the track or driving backwards never counts), and
  a lap/time HUD with your best lap. After the flag the car rolls out and
  the final time stays up; Reset starts a fresh race.
- Hazards on the racing line: a mud bog pinching the bottom straight, a
  water pool clipping the top-right exit, and an oil slick on the right
  straight — each with its own grip/drag feel, and mud/water print tire
  trails back onto the asphalt for a while after you drive through.
- Every run is now recorded as seed + input stream (tiny, deterministic)
  — the raw material for future replays, ghosts, and hiscores.
- Two more control schemes in the switcher: **Two-zone** (hold = gas,
  half of the screen picks the turn) and a real **One-touch** (permanent
  gas; hold = turn, quick tap = flip turning direction).
- Smooth marks on small phones: skid marks now render as a few batched
  strokes instead of one per segment (choppy on iPhone 13 mini once they
  piled up), record at half tick rate, and keep a smaller budget — oldest
  marks still fade out first. D-pad gets a third step per axis for finer
  throttle/steer modulation.
- Controls, round two (first on-device feedback): a **virtual d-pad** is
  the new default — it appears where the thumb lands (within the player's
  control zone, tinted the car's color), steers while coasting, and
  quantizes each axis to half/full steps instead of binary or full-analog;
  pull back to brake/reverse. A button next to Reset switches schemes
  in-run (D-pad / Slide / One-touch) for A/B on the device.
- First drivable prototype: one car, one track, thumb-driven — drive laps
  with the arcade touch-pad (thumb down = gas, slide sideways = steer,
  release = coast) and feel the drift. Skid marks burn onto the asphalt in
  hard slides and scuff the grass when you run wide.
- Project scaffolding: XcodeGen project (iOS target), `SkidCore` package
  with the deterministic fixed-timestep drift sim (surfaces, layer-aware
  track model, checkpoint gates, wall bounce) and its tests, pinned
  lint/format tooling, and CI (lint, tests + coverage, simulator build).
