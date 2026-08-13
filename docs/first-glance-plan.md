# First-glance usability

Three reported problems, all versions of the same one: **at the moment a player
most needs to know what to do and which car is theirs, the game tells them
nothing.** The information exists — it is just not on screen until after it
stops mattering.

Ordered cheapest first; each ships on its own.

## 1. Car colors that are actually distinguishable

**Measured, not eyeballed.** Perceptual distance (CIELAB ΔE) across the current
palette `[.red, .yellow, .cyan, .purple, green, .orange, .pink, .white]`:

| pair | ΔE | |
|:--|--:|:--|
| red vs **pink** | **21** | too close — a 20-unit sprite in motion |
| yellow vs orange | 33 | marginal |
| cyan vs white | 45 | fine |
| red vs orange | 48 | fine |

Below about 25 two cars read as the same color once they are small, moving, and
overlapping. Red/pink fails outright and both are in the first six seats.

### What actually matters: finding YOUR car

Two clarifications that make this much more tractable than "nine mutually distinct
colors":

- **A glow on every car** handles contrast against the background, which matters
  once road surfaces vary (snow, gravel — see the roadmap). So the palette does
  not have to survive every possible surface on its own.
- **Recognizing your own car is the goal**, not telling all nine apart. Nobody
  needs to know which shade the AI in fourth place is.

So the bar is: *your* color must stand clear of the field, in any vision type.

### The palette, chosen for accessibility

The obvious answer fails. A hue-spread nine (red · orange · yellow · green · teal ·
cyan · blue · purple · magenta) measures 32.8 in normal vision and then collapses,
because nine **hues** cannot stay distinct once hue discrimination does:

| vision | worst ΔE, hue-spread nine |
|:--|--:|
| normal | 32.8 |
| protanopia | 13.3 |
| deuteranopia | **9.9** |
| tritanopia | **8.7** |

What carries legibility is **lightness spread**. Searching hue × saturation × value
for the nine whose worst pair survives all three CVD simulations:

```
yellow   (0.95, 0.95, 0.05)   L* 93
lime     (0.40, 1.00, 0.70)   L* 91
pink     (1.00, 0.40, 0.85)   L* 66
violet   (0.85, 0.40, 1.00)   L* 63
olive    (0.47, 0.62, 0.03)   L* 60
magenta  (0.95, 0.05, 0.50)   L* 53
blue     (0.27, 0.05, 0.95)   L* 34
maroon   (0.62, 0.03, 0.18)   L* 33
indigo   (0.33, 0.03, 0.62)   L* 25
```

| vision | worst pair | your car vs nearest rival |
|:--|--:|--:|
| normal | 27.4 | ≥27.4 |
| protanopia | 29.3 | ≥29.3 |
| deuteranopia | 26.3 | ≥26.3 |
| tritanopia | **24.7** | **≥24.7** |

So **every seat sits ≥24.7 from its nearest rival in every vision type**, against
the current palette's 21.0 in *normal* vision alone. L* runs 25 → 93, which is the
property doing the work.

Contrast with the track is fine — lowest is 27 (olive on grass, maroon on a red
kerb), everything else 44+. Asphalt is `white: 0.62`, a *light* gray, so the dark
colors contrast well rather than vanishing. The glow above is what generalises
that to surfaces yet to exist.

### What must NOT be done: muting the AI cars

Local-vibrant / AI-recessive is a good instinct and the wrong lever, measurably:

| AI saturation | worst ΔE across the nine |
|--:|--:|
| 1.00 | 24.7 |
| 0.70 | 15.6 |
| 0.55 | **6.5** |

Desaturating collapses the palette, and HSV desaturation *raises* L\* (maroon
33 → 43), flattening exactly the spread the accessibility rests on.

Distinguish your own car by something that is **not the color** — which is what
§2 below already proposes: a ring, and the seat number. There is a second reason
too: **"local" is a per-screen property.** Under networking the same car is local
on one device and remote on another, so it cannot live in a shared palette.

### A pool to pick from, in the lobby

The better model, and it changes the requirement rather than the palette: colors
are **chosen in the lobby** once everyone is connected, not assigned by seat index.

**But a 16-color pool cannot be mutually distinct.** Measured — the best
achievable worst-pair ΔE across normal + all three CVD types:

| pool size | best possible worst pair |
|--:|--:|
| 9 | 21.6 |
| 12 | 15.0 |
| 16 | **11.2** |

So sixteen accessible-in-all-vision-types colors do not exist; at 16 the closest
pair is worse than today's problematic red/pink. That is a fact about human vision,
not about effort.

Which is fine, because a pool has a **different** requirement — and the decision
here is deliberately *not* to enforce anything:

**Players pick, including badly.** Somebody who takes the second-lightest blue when
a similar one is gone has made a choice, and greying options out or nagging about
ΔE would be the app second-guessing its own users. Two similar cars is a
consequence they can see and fix themselves.

So the palette's job shrinks to one thing that genuinely matters: **the DEFAULT
assignment is the accessible nine.** A race nobody fiddles with is legible; the
extra pool entries are self-expression. That is also the only part worth testing,
which is a good sign it is the right split.

Worth noting the ordering consequence: with a lobby, "seat order" stops being a
color question. The nine below stay the **defaults**, in separation order, for
anyone who does not pick.

### How many colors can we have? — and the sheen is the real limit

**Nine is about the ceiling for mutually-distinct**, measured: the best achievable
worst pair is 21.6 at nine, 15.0 at twelve, 11.2 at sixteen. That is a fact about
human vision.

But before adding a tenth, there is a **much larger loss already in the renderer**.
Every car is drawn with a white sheen across its front half (up to opacity 0.55) as
the facing cue — a lit nose. Measured against the palette:

| what is compared | worst pair ΔE |
|:--|--:|
| body color, as chosen | **24.7** |
| **front half, sheen 0.55** | **9.1** |
| front half, sheen 0.40 | 12.9 |
| front half, sheen 0.25 | 17.0 |

**The nose of every car is more than half white**, so on the half a player looks at
first, nine carefully-chosen colors collapse to worse than the palette this work
set out to replace. No palette can fix that; only the drawing can.

Which answers the shapes question: **shape and shading are worth more than more
colors.** Options, cheapest first:

- **Tone down the sheen** and let the *tail* carry the color — or gradient the
  other way, so the identifying end is the saturated one.
- **Keep the sheen but tint it** with the car's own color rather than white, so a
  lit nose stays a *blue* lit nose.
- **Shape** — a different silhouette per car is the strongest cue of all and
  survives both CVD and small size, but it is real art work and it fights the
  "open-wheeler" look the renderer commits to today.
- **A pattern** — stripe, roundel, number — which is what real racing uses
  precisely because color alone does not scale past a handful of cars.

### Two-tone cars — the answer to "how many colors"

Making the nose a **second palette color** instead of a white wash turns the
facing cue into part of the identity, and the arithmetic is decisive:

**9 bodies × 8 noses = 72 distinct liveries**, from the same nine measured colors.
That is far past the sixteen options wanted from a picker, and every one is
identifiable, because both halves are real palette colors rather than a wash.

Note what does *not* work: simply lightening the car's own color for the nose. It
keeps identity but the noses then differ by only ΔE 9–14 from each other, so it
solves nothing that the white wash did not.

Consequences worth thinking about before building:

- **The facing cue must survive.** Nose and tail need enough contrast *within* one
  car to read direction at speed — so a livery is a *pair* with a minimum internal
  ΔE, which is a testable rule rather than a judgement.
- **A pattern still beats both** at telling nine cars apart (real racing uses
  numbers and stripes for exactly this reason), but two-tone is much cheaper than
  new silhouettes and reuses everything already measured.
- **Shapes stay a later question.** They are the strongest cue and the most art
  work, and they fight the open-wheeler look the renderer commits to today.

Recommendation, in order: **fix the sheen** (measure on device — it may just want
toning down), then **two-tone** for the picker, and treat shapes as separate. Nine
colors plus an honest nose beats sixteen colors behind a white wash.

### Seat order (the defaults)

The first four are the seats a 1–4 player game uses, so they should be the four
*most* separated rather than the first four listed. Keep both as tests — a minimum
ΔE across all nine **in every CVD simulation**, and a higher bar across the first
four — so a future tweak cannot quietly undo either.

## 2. Which car is mine, at the start

The countdown is exactly when a player needs this and exactly when nothing says
it. `Race.Phase.countdown(remainingTicks:)` already exists and the HUD already
reads it (`RaceHUD` switches on it), so there is a clean hook and no new state.

Proposed, per the report: during the countdown only, draw over each **human**
car:

- a **number bubble** in the player's color — the seat number, so it matches
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

**The fix**: give each control a **resting origin at the center of its own
zone**, drawn dimmed, and let touch-down move it as it does now. So the control
is always visible, always in a predictable place, and the existing
touch-anywhere-in-your-zone behavior is unchanged.

Two things to get right:

- **Dimmed, not solid.** It is a hint at rest and a control in use; the existing
  `opacity(0.12)` disc is already close to the right weight.
- **It must not lie.** The resting position has to be somewhere touching would
  actually work, or the hint teaches the wrong thing. The zone center qualifies
  (`ZoneChrome.rect.mid`), which is also what the report suggested.

Worth considering: fade the resting hint out after the player's first few
touches in a session, so it teaches without permanently occupying the zone. That
is a nicety — the always-on version is the fix.

## Why these three together

They are one bug from the player's side: *the first ten seconds don't explain
themselves.* Colors make the cars distinct, markers say which one is yours, and
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
