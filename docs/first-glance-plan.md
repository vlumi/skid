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

### What actually matters: finding YOUR car

Two clarifications that make this much more tractable than "nine mutually distinct
colours":

- **A glow on every car** handles contrast against the background, which matters
  once road surfaces vary (snow, gravel — see the roadmap). So the palette does
  not have to survive every possible surface on its own.
- **Recognising your own car is the goal**, not telling all nine apart. Nobody
  needs to know which shade the AI in fourth place is.

So the bar is: *your* colour must stand clear of the field, in any vision type.

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
kerb), everything else 44+. Asphalt is `white: 0.62`, a *light* grey, so the dark
colours contrast well rather than vanishing. The glow above is what generalises
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

Distinguish your own car by something that is **not the colour** — which is what
§2 below already proposes: a ring, and the seat number. There is a second reason
too: **"local" is a per-screen property.** Under networking the same car is local
on one device and remote on another, so it cannot live in a shared palette.

### A pool to pick from, in the lobby

The better model, and it changes the requirement rather than the palette: colours
are **chosen in the lobby** once everyone is connected, not assigned by seat index.

**But a 16-colour pool cannot be mutually distinct.** Measured — the best
achievable worst-pair ΔE across normal + all three CVD types:

| pool size | best possible worst pair |
|--:|--:|
| 9 | 21.6 |
| 12 | 15.0 |
| 16 | **11.2** |

So sixteen accessible-in-all-vision-types colours do not exist; at 16 the closest
pair is worse than today's problematic red/pink. That is a fact about human vision,
not about effort.

Which is fine, because a pool has a **different** requirement: only the colours
actually *picked* need to be distinct. Two ways to get there:

- **Warn** when two picks are close, and let people do it anyway. Honest, no
  nannying.
- **Grey out** anything within ~20 ΔE of a taken colour. Cannot go wrong, but the
  options thin out as the lobby fills.

Either way the property that matters is the same: **the default assignment must be
the accessible nine**, so a race nobody fiddles with is legible by default. The
extra pool entries are then self-expression rather than a trap — someone who
insists on two similar blues has chosen that.

Worth noting the ordering consequence: with a lobby, "seat order" stops being a
colour question. The nine below stay the **defaults**, in separation order, for
anyone who does not pick.

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
