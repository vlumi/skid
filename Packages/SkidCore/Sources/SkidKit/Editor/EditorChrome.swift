import SkidCore
import SwiftUI

/// The editor's two chrome bars: the top row of whole-track actions, and the palette
/// along the bottom.
///
/// Split from `EditorView.swift` to keep that file inside its length budget. Both are
/// laid out rather than floated over the map, so they cannot collide with it on a
/// small screen.
extension EditorView {
    var topBar: some View {
        HStack(spacing: 8) {
            // EVERY top-bar button is an icon. Text pills wrapped to
            // "Ce/nte/r" on a small phone; icons fit, and the accessibility
            // label carries the meaning.
            iconButton("checkmark", "Done") {
                game.backToMenu()
            }
            Spacer(minLength: 4)
            // **The track's name, where you are looking at the track** — and the door
            // to its properties. Copy/paste of the share code moved into that sheet:
            // they are track-level operations used rarely, and the two of them plus
            // the attribution seal were most of a row this bar no longer spends.
            nameChip
            Spacer(minLength: 4)
            iconButton("arrow.up.left.and.arrow.down.right", "Fit view") {
                resetView()
            }
            // **Opens the shelf, rather than clearing the canvas.** It used to call
            // `editorReset`, which wiped the current track as an undoable edit — the
            // only "new" available when there was one slot. Now that the library can
            // hold many, the honest action is to go and pick one (or start a new one
            // there), leaving this track saved.
            iconButton("square.grid.2x2", "My tracks") {
                game.shelfCameFromEditor = true
                game.showingTrackShelf = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// The edited track's name, or a prompt when it has none yet — and the door to
    /// everything else that belongs to the whole track (see `TrackPropertiesSheet`).
    ///
    /// A brand-new canvas has no library row — nothing is written until there is more than
    /// a start piece — so there is genuinely nothing to name yet. `renameEditedTrack`
    /// remembers a name given now and applies it when the row appears, so this is tappable
    /// either way rather than being disabled until the track is worth saving.
    private var nameChip: some View {
        Button {
            renamingTrack = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "pencil.line").font(Retro.caption)
                if let name = game.editedTrackName {
                    Text(verbatim: name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("Name this track", bundle: .module)
                        .lineLimit(1)
                }
            }
            .font(Retro.caption)
            .foregroundStyle(Retro.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Retro.panel)
            .overlay(RetroBevel(thickness: 2))
        }
    }

    func paletteBar(walk: WalkResult) -> some View {
        VStack {
            VStack(spacing: 10) {
                // Whole-track transforms, on the row above the hint: LAID OUT
                // rather than floated over the map, so they can't collide with
                // the palette on a small screen (a corner-anchored pad landed
                // right on top of it on an SE).
                // Two rows, grouped by what they act on. Nothing here floats over
                // the map: chrome on the road is what caused accidental deletes.
                let building = game.editorMode == .build
                if building {
                    // The SELECTED PIECE's strip: steppers and its properties, in a
                    // fixed place so the bin never moves. Always present (disabled
                    // empty) rather than appearing on selection — a row that comes and
                    // goes resizes the map, which moves the piece you just tapped.
                    HStack(spacing: 8) {
                        selectionRow
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    // Actions on the left, MODES on the right. A mode reads as a
                    // pressed-in button while it is on — see `Retro`. Levels and Gates
                    // stand down while the transforms are expanded, which wants the
                    // whole row on an SE.
                    HStack(spacing: 8) {
                        transformPad
                        if !showTransforms {
                            Spacer()
                            levelsToggle
                            modeToggle
                        }
                    }
                    .padding(.horizontal, 12)
                } else {
                    HStack(spacing: 8) {
                        Spacer()
                        modeToggle
                    }
                    .padding(.horizontal, 12)
                }
                if game.editorMode == .gate {
                    gateModeHint(walk)
                } else {
                    buildStatus(walk: walk)
                    // The label over the sticky cluster: pitch, radius and the rail
                    // toggle all shape the NEXT piece laid, and nothing used to say
                    // so — the rail toggle in particular read as an orphaned second
                    // control for railings rather than a sibling of pitch.
                    Text("NEXT PIECE", bundle: .module)
                        .font(Retro.caption)
                        .foregroundStyle(Retro.onGroundSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    mainRow(walk: walk)
                    // The hotbar appears when it has something to hold; empty slots
                    // are dead space, and today its only entry is experimental.
                    if !EditorView.hotbarPieces(experimental: EditorView.experimentalGaps).isEmpty {
                        hotbarRow(walk: walk)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

/// The rename prompt behind the editor's name chip.
///
/// A modifier rather than an inline `.alert` so `EditorView` stays inside its length
/// budget, and it sits beside `nameChip` — the control it belongs to.
