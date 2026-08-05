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
                    game.backToSetup()
                }
                Spacer()
                iconButton("doc.badge.plus", "New track") {
                    game.editorReset()
                }
                iconButton("arrow.up.left.and.arrow.down.right", "Fit view") {
                    resetView()
                }
                // Re-center the layout on the canvas. Closing a loop does this
                // automatically; the button is for tracks built before that, or
                // reshaped since.
                iconButton("scope", "Center on canvas") {
                    game.editorCenterOnCanvas()
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
            Spacer()
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
                HStack(spacing: 8) {
                    let building = game.editorMode == .build
                    if building { transformPad }
                    Spacer()
                    if building {
                        railBuildToggle
                        levelsToggle
                    }
                    modeToggle
                }
                .padding(.horizontal, 12)
                if game.editorMode == .gate {
                    gateModeHint(walk)
                } else {
                    buildStatus(walk: walk)
                    mainRow(walk: walk)
                    // The hotbar returns when it has something to hold (jumps,
                    // gaps, decorations); five empty slots are dead space.
                    if !EditorView.hotbarPieces.isEmpty {
                        hotbarRow(walk: walk)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}
