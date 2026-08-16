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
        VStack {
            HStack {
                // EVERY top-bar button is an icon. Text pills wrapped to
                // "Ce/nte/r" and "Co/pie/d" on a small phone, and adding more only
                // made it worse — seven words never fit one row. Icons do, and the
                // accessibility label carries the meaning.
                iconButton("checkmark", "Done") {
                    game.backToMenu()
                }
                Spacer()
                // **Opens the shelf, rather than clearing the canvas.** It used to call
                // `editorReset`, which wiped the current track as an undoable edit — the
                // only "new" available when there was one slot. Now that the library can
                // hold many, the honest action is to go and pick one (or start a new one
                // there), leaving this track saved.
                iconButton("square.grid.2x2", "My tracks") {
                    game.shelfCameFromEditor = true
                    game.showingTrackShelf = true
                }
                iconButton("arrow.up.left.and.arrow.down.right", "Fit view") {
                    resetView()
                }
                // Copy the share code out — how a design becomes a built-in, or
                // gets kept somewhere until there's a real track library. The icon
                // flips to a tick to confirm, since there's no text to change.
                iconButton(copiedCode ? "checkmark.circle.fill" : "doc.on.doc", "Copy code") {
                    copyCode()
                }
                // Long-press copies the SHORT code, without a signature.
                .simultaneousGesture(
                    LongPressGesture().onEnded { _ in copyCode(signed: false) })
                // …and paste one back in to load it. Separate buttons on purpose:
                // one that did both could silently replace the track you're on.
                // A failed paste shows a warning icon rather than "Bad code".
                iconButton(
                    pasteFailed ? "exclamationmark.triangle.fill" : "doc.on.clipboard",
                    "Paste code"
                ) {
                    pasteCode()
                }
                attributionChip
            }
            .padding()
            // **The track's name, where you are looking at the track.**
            //
            // Renaming lived only behind a long press on a shelf tile, which is both
            // hidden and the wrong place: you name a track when you have just finished
            // building it, not when picking one to open. Tapping this renames.
            nameChip
            Spacer()
        }
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
                } else {
                    Text("Name this track", bundle: .module)
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
            Spacer()
            VStack(spacing: 10) {
                // Whole-track transforms, on the row above the hint: LAID OUT
                // rather than floated over the map, so they can't collide with
                // the palette on a small screen (a corner-anchored pad landed
                // right on top of it on an SE).
                // Two rows, grouped by what they act on. Nothing here floats over
                // the map: chrome on the road is what caused accidental deletes.
                let building = game.editorMode == .build
                if building {
                    // The SELECTED PIECE, in a fixed place so the bin never moves.
                    HStack(spacing: 8) {
                        selectionRow
                        Spacer()
                        levelsToggle
                        modeToggle
                    }
                    .padding(.horizontal, 12)
                    // The whole track, and the edit history.
                    HStack(spacing: 8) {
                        transformPad
                        Spacer()
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
