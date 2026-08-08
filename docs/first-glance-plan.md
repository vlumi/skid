# First-glance usability

Three reported problems, all versions of the same one: **at the moment a player
most needs to know what to do and which car is theirs, the game tells them
nothing.** The information exists — it is just not on screen until after it
stops mattering.

Ordered cheapest first; each ships on its own.

## 1. Car colours that are actually distinguishable

**Measured, not eyeballed.** Perceptual distance (CIELAB ΔE) across the current
palette `[.red, .yellow, .cyan, .purple, green, .orange, .pink, .white]`:

| pair | ΔE | |
|:--|--:|:--|
| red vs **pink** | **21** | too close — a 20-unit sprite in motion |
| yellow vs orange | 33 | marginal |
| cyan vs white | 45 | fine |
| red vs orange | 48 | fine |

Below about 25 two cars read as the same colour once they are small, moving, and
overlapping. Red/pink fails outright and both are in the first six seats.

**The fix**: swap pink → magenta and nudge yellow/orange apart. Worst pair rises
**21 → 36**, and the four seats that matter most (the common 1–4 player case) sit
at ΔE 82–159 from each other:

```
red      (0.94, 0.21, 0.18)
yellow   (1.00, 0.82, 0.10)
cyan     (0.30, 0.80, 0.98)
purple   (0.68, 0.32, 0.90)
green    (0.25, 0.80, 0.30)
orange   (1.00, 0.52, 0.05)
magenta  (0.95, 0.15, 0.75)     ← was pink
white    (1.00, 1.00, 1.00)
```

Order matters as much as the values: `carPalette`'s first four are the seats a
1–4 player game uses, so they must be the four most separated. Keep the check as
a **test** — assert a minimum ΔE across the palette, and a higher one across the
first four — so a future colour tweak cannot quietly reintroduce this.

**Also worth checking against the track**, which this analysis did not: red on
red/white kerbs, and white on the light grey of a raised deck. The palette is
only half the question; contrast with the background is the other half.

## 2. Which car is mine, at the start

The countdown is exactly when a player needs this and exactly when nothing says
it. `Race.Phase.countdown(remainingTicks:)` already exists and the HUD already
reads it (`RaceHUD` switches on it), so there is a clean hook and no new state.

Proposed, per the report: during the countdown only, draw over each **human**
car:

- a **number bubble** in the player's colour — the seat number, so it matches
  whatever the setup screen and HUD call them
- an **arrow / ring** around the car so it is findable on a crowded grid
- the number **rotated to face its own player**, which the rig already knows:
  `ZoneChrome.up` is exactly that vector, and `OverlayRenderer` already uses it
  to place each player's edge tab

Then fade out as the lights go green — it is orientation, not HUD.

Open questions worth deciding before building:

- **AI cars too, or humans only?** Humans only is less clutter; numbering
  everything makes the grid legible but adds nothing a player acts on.
- **Fade, or hard cut at green?** A fade risks obscuring the first corner; a cut
  risks the marker vanishing before it has been read.
- **Does it survive a restart?** After a crash-and-restart the same confusion
  applies, so it should probably key off the countdown phase rather than "first
  race".

## 3. The control pad, visible before it is touched

Today `origin` is nil until touch-down (`ControlSources.swift`: set in `began`,
cleared in `ended`), and the overlay renderers `compactMap` on it — so **nothing
is drawn until the player already knows where to press.** That is precisely
backwards for a first-time player, and it is the report's strongest point.

Note the default scheme is **casual** (the aim stick), not the pro d-pad, so this
has to fix the *aim* overlay first, or fix both.

**The fix**: give each control a **resting origin at the centre of its own
zone**, drawn dimmed, and let touch-down move it as it does now. So the control
is always visible, always in a predictable place, and the existing
touch-anywhere-in-your-zone behaviour is unchanged.

Two things to get right:

- **Dimmed, not solid.** It is a hint at rest and a control in use; the existing
  `opacity(0.12)` disc is already close to the right weight.
- **It must not lie.** The resting position has to be somewhere touching would
  actually work, or the hint teaches the wrong thing. The zone centre qualifies
  (`ZoneChrome.rect.mid`), which is also what the report suggested.

Worth considering: fade the resting hint out after the player's first few
touches in a session, so it teaches without permanently occupying the zone. That
is a nicety — the always-on version is the fix.

## Why these three together

They are one bug from the player's side: *the first ten seconds don't explain
themselves.* Colours make the cars distinct, markers say which one is yours, and
a resting pad says what to do with your thumb. Any one alone leaves the other two
gaps open, which is why they belong in one pass even though they ship separately.

## Verification

`make test`, both linters, `make build-ios`, by exit code as usual.

- The palette gets a **real test** (minimum ΔE), since it is arithmetic.
- The other two are **look-at-it-on-device** changes, and honest about that:
  nothing here can be proven by a unit test. Assert what is assertable — that a
  countdown marker exists for each human car and vanishes after the countdown,
  that a resting origin sits inside its own zone — and take the rest to a
  simulator.
