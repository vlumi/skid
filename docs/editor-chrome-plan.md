# Editor chrome: grouping by purpose

## The problem

Reported from device, three symptoms of one cause:

- **Accidental deletes.** The piece actions (bin, markings) float 34 pt above the
  selected piece — over the road you tap next. `.position(x: anchor.x, y: anchor.y - 34)`.
- **Buttons and labels no longer fit.** `Rails` and `Levels` are labelled pills in a
  row that also holds the transform pad and `Gates`; `Levels` now shows a number, so
  its width changes as it cycles.
- **Two identical ticks.** `Done` is `checkmark`; `Copy code` flips to
  `checkmark.circle.fill` on success. Three `doc.*` icons sit in a row besides.

The cause is not any one of these: **controls are grouped by when they were added,
rather than by what they act on.** ~24 controls, in five clusters that interleave four
unrelated concerns.

## Inventory

| group | acts on | controls | today |
|---|---|---|---|
| document | the track as a file | Done, New, Copy, Paste | top row |
| view | the camera | Fit, Center | top row |
| edit | the undo stack | Undo, Redo | transform pad |
| track | the whole layout | rotate L/R, raise, lower, reverse | transform pad |
| — | — | (all five are **rare**: usually once, at the start) | — |
| selection | one piece | bin, markings, (rails) | **floating on the map** |
| mode | what a tap means | Rails, Levels, Gates | bottom row |
| palette | what to lay next | shapes, curve variants, hotbar | bottom |

`Undo`/`Redo` sit in the transform pad but belong to none of it: they act on the edit
history, not the layout.

## Frequency matters as much as grouping

The transform pad holds seven buttons, and they are not alike:

| | frequency |
|---|---|
| rotate ×2, raise, lower, reverse | **rare** — usually once, when a track is first laid out |
| undo, redo | **constant** — every edit |

Lumping them is why the row is seven wide. Measured against the iPhone SE width the
codebase designs for:

| | width |
|---|---:|
| transform pad (7 buttons) | 280 pt |
| Rails + Levels + Gates (labelled pills) | ~198 pt |
| **total** | **478 pt on a 320 pt screen — overflows by 158** |

That overflow is the reported "buttons and their labels don't fit at all anymore".

Putting the five rare transforms behind **one** button, and every mode control on an
icon, brings the row to 240 pt — 75% of the width, with room to spare:

| | width |
|---|---:|
| `[transform]` + undo + redo | 120 pt |
| Rails / Levels / Gates as icons | 120 pt |
| **total** | **240 pt** |

Undo and redo stay visible: they are the most-used controls in the editor and the
ones you reach for without looking.

## The budget rules out one row per group

Measured against the iPhone SE viewport (320×568) the codebase already designs for:

- one row per group: **318 pt of chrome, leaving the map 44%**
- two rows top, two bottom, plus palette: **296 pt, leaving 48%**

The map is the thing being edited and should have the majority of the screen. So
groups cannot each own a row: **some must be contextual**, present only when they
apply.

## Proposal

**The rule: a control lives where its object is, and nothing that acts on a piece may
move.**

```
┌─────────────────────────────────────┐
│ [Done]                    [⋯][Fit]  │  document · view
├─────────────────────────────────────┤
│                                     │
│              the map                │  ~50% of the screen
│                                     │
├─────────────────────────────────────┤
│ [bin][brush][rail]      [Lv][Gates] │  SELECTION (fixed) · modes
├─────────────────────────────────────┤
│ [⤢ transform] [↶][↷]      complete  │  rare transforms · edit history
├─────────────────────────────────────┤
│ palette / hotbar                    │
└─────────────────────────────────────┘
```

Contextual, not always-on:

- **The selection row** is present always but **disabled** when nothing is selected —
  greyed rather than absent, so the row does not reflow and the bin never moves.
- **`New` / `Copy` / `Paste`** move behind a single document button (`…`), since they
  are rare and dangerous next to `Done`. That also removes the three-`doc.*` cluster
  and the duplicate tick.
- **The five rare transforms** (rotate ×2, raise, lower, reverse) collapse behind one
  `transform` button, since they are laid-out-once operations. Undo and redo stay
  visible beside it — they are the most-used controls in the editor.
- **The transform row** appears only in build mode, as now.

### What this fixes

- **Deletes**: the bin is in a fixed place and never over the map, so trimming is
  tap-piece, tap-bin, tap-piece, tap-bin without the target moving.
- **Fit**: every group is one purpose per row, so widths are predictable and icons
  suffice — the call the top bar already made for itself.
- **Ticks**: `Done` becomes the only tick; `Copy` lives behind the document menu and
  can confirm with text there.

### Open questions for device

- Does the selection row read as belonging to the selected piece when it is nowhere
  near it? A subtle connector, or tinting the row to match the selection highlight,
  may be needed.
- Is `Levels` as an icon-plus-number legible at a glance, or does the number need to
  be the whole button?
- Does the document menu hide `Copy` too well? It is the main sharing route.

## Not doing

- **Moving piece actions to a map corner.** Considered; it trades one covered area for
  another, and on a stacked track there is no corner that is reliably empty.
- **A single mode picker** replacing Rails/Levels/Gates. They compose with build mode
  rather than replacing it, so a segmented control would misrepresent them.
