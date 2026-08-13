# Experimental features

Work that is finished enough to keep and unfinished enough to hide.

```sh
make run-iphone EXPERIMENTAL=1     # drive a build that has them
make build-ios  EXPERIMENTAL=1
make test       EXPERIMENTAL=1     # tests, with the gated code compiled in

SKID_EXPERIMENTAL=1 swift build    # the package directly
```

Anything else — a plain build, a debug build, a release build, and CI — leaves
them out. **No regeneration is needed either way:** the Xcode setting resolves
`$(SKID_EXPERIMENTAL_FLAG)` at build time, so `EXPERIMENTAL=1` changes one build
and nothing on disk.

Two mechanisms, because there are two build systems:

| | how it is set |
|:--|:--|
| Xcode app target | `SKID_EXPERIMENTAL_FLAG=SKID_EXPERIMENTAL` build setting (`project.yml` defaults it empty) |
| SwiftPM package | `SKID_EXPERIMENTAL=1` in the environment, read by `Package.swift` |

Both define the same `SKID_EXPERIMENTAL` compilation condition, so the Swift
code has one thing to check.

**How much is actually removed.** `EditorView.experimentalGaps` is a `#if`-backed
constant, but the call sites test it with an ordinary `if`. So the gated views are
still *type-checked* in a stock build — the compiler sees them, the optimiser drops
the branch. That is deliberate: a `#if` around every call site would let gated code
rot silently, and it is the reason CI builds the on path rather than trusting it.

The guarantee is therefore about **reachability, not binary size**: in a stock build
nothing offers the controls, `hotbarPieces` is empty, and no path reaches them. If a
future experiment needs to be genuinely absent from a shipped binary — something
costly, or something that must not be discoverable — that one wants `#if` at the call
site, and the cost is that it only compiles when the flag is on.

## Why not `#if DEBUG`

Because **an ordinary debug build is the one being driven** while testing
everything else. Tying experiments to `DEBUG` puts half-finished chrome in the
way of every unrelated device check, which is precisely what the flag is for
avoiding. `SKID_EXPERIMENTAL` is off unless asked for, in every configuration.

## Why not a settings toggle

A switch in the UI is one more thing to explain about a feature whose problem is
usually that it needs explaining. There is nothing here a player should have to
decide, and a persisted toggle would outlive the experiment.

## The rule: hide the CONTROLS, keep the FORMAT

This is what makes the flag cheap enough to use freely.

A flag may hide **authoring**: a palette button, a mode, an editor gesture. It
must not narrow what the game can **load, race or share**. A track built in an
experimental build has to decode, compile, race and round-trip on a stock one —
it may well arrive as a share code from another device, and a code that only
some builds understand is a broken format rather than a hidden feature.

Concretely, for each experiment:

- the catalog keeps its pieces
- the share code keeps its section
- the compiler and the sim keep their handling
- **only the editor's controls disappear**

Pin it with tests that never read the flag: decode a track using the feature,
compile it, race it. `ExperimentalGapsStayRaceableTests` is the worked example.

CI runs the suite with the flag **off** (that is what ships) and additionally
*builds* with it on, so gated code cannot rot unnoticed behind its own flag.

## What is behind it today

### Gaps and warps (the jump-building blocks)

The Gap piece on the palette hotbar, and the up/down arrows that drop the road a
level. Hidden because the *authoring* is the doubtful part, not the result: a
warp is a thing you cannot see, adjusted by arrows that act on wherever you
happen to be building, and a gap is a piece whose whole content is nothing. Both
need explaining, on a palette that is otherwise "tap a shape".

The physics they were built for are **not** behind the flag and never should be:
falling off a railless bridge, off a ramp flank, or off a road that ends all
follow one arc, and a ramp with nothing above it keeps its full slope. Those are
finished, and they apply to tracks that contain no gaps at all.

See `docs/jump-pieces-plan.md` for how the design got here.

### The tuning panel, opened by shaking the device

Twenty-five of the app's twenty-eight persisted settings are `skid.sim.*`,
`skid.aim.*` and friends: dials for on-device A/B tests, not player settings. They
are **not shipping**, so the flag here is doing something different from the piece
work above — that hides authoring for a format that ships anyway, while this removes
a developer tool from the product entirely.

Two things follow from that difference:

- **A shake, not a button.** The dials used to be a `Tuning` button in the pause
  menu, which put a developer control in a player's way *and* made the panel
  reachable only from inside a race — so tuning anything about the menus, the editor
  or the lobby meant starting a race first. A shake is reachable everywhere and
  occupies no pixels, so the menus can be designed as if the panel did not exist.
- **Compiled out, not hidden.** A hidden control still ships. `tuningOnShake` is the
  identity function without the flag, and `TuningPanel` is referenced from exactly
  one place — inside the guard — so a production binary has no route to it.
  `ShakeToTuneTests` asserts the wiring *with* the flag and the identity *without*
  it, so a regression fails whichever way the suite runs.

The gesture itself is UIKit's own `motionEnded` shake — the same recognizer behind
shake-to-undo — so there is no accelerometer polling, no threshold to tune, and it
feels like every other iOS shake because it is that gesture. It cannot be exercised
in a unit test, since the event is delivered to a real window.

## Retiring a flag

Two honest endings, and it is worth deciding which one you are heading for:

- **Promote it.** Delete the condition, keep the code. The controls ship.
- **Remove it.** Delete the controls, and decide separately whether the format
  keeps its pieces. Usually it should: an id costs a byte, and a track someone
  already built and shared should not stop working because the button went away.

A flag with no owner and no verdict is the failure mode — it accumulates
untested code paths. **Every flag has a deadline on the 1.0 checklist** in
[ROADMAP.md](../ROADMAP.md), so none of them can quietly become permanent.

For gaps and warps specifically, the verdict is not "was the feature right" —
the pieces work and race fine. It is whether a different editor UI makes them
workable. Worth a fresh attempt before deciding.
