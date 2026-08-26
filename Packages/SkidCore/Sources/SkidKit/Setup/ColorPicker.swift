import SkidCore
import SwiftUI

/// **A seat's color swatch: tap to cycle, long-press for the whole palette.**
///
/// Two gestures because they answer different questions. Cycling is the fast one
/// — "not this, the next" — and it is all anybody needs with two players and nine
/// colors. The palette answers "which ones are there, and can I have that one",
/// which cycling can only answer by walking the ring and remembering.
///
/// One declared gesture rather than a `Button` plus a long press: those compete,
/// and the tap then fires only sometimes (the editor's hotbar hit exactly that,
/// and its level button is written this way for the same reason).
struct SeatColorSwatch: View {
    @ObservedObject var game: CouchGame
    /// The seat this swatch belongs to — an index into `colorIndices`.
    let slot: Int
    /// How wide the disc draws. The list row wants a small one, the options
    /// screen a thumb-sized one.
    var diameter: CGFloat = 26
    /// The ring around the disc. White on the list's dark row, dark ink on the
    /// options screen's grey panel — each is what reads against its background,
    /// and neither is a color the palette owns.
    var ring: Color = .white.opacity(0.85)
    /// Opens the palette sheet. Owned by the parent, which has the sheet.
    let showPalette: () -> Void

    var body: some View {
        Circle()
            .fill(CouchGame.palette[game.colorIndices[slot % game.colorIndices.count]])
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(ring, lineWidth: 2))
            .contentShape(Circle())
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in showPalette() }
                    .exclusively(
                        before: TapGesture().onEnded { game.cycleColor(slot: slot) })
            )
            .accessibilityLabel(Text("Car color", bundle: .module))
    }
}

/// **The whole palette at once, with the taken colors shown as taken.**
///
/// The grid is the argument for existing: cycling never shows what is on offer,
/// and it cannot say *why* a color it skipped is unavailable. Here the colors
/// another racing seat holds are drawn struck through and refuse the tap, with
/// the holder named underneath — so "why can't I be blue" answers itself.
///
/// A seat's OWN color is not unavailable, it is selected — the one marked with
/// the DOS caret the rest of the app uses for a current choice.
struct ColorPaletteSheet: View {
    @ObservedObject var game: CouchGame
    let slot: Int
    let dismiss: () -> Void

    /// Which racing seat holds each color — the only seats that block one. Idle
    /// slots hold colors too (the array is a permutation of the palette), but
    /// nobody is driving them, so they are free to take.
    private var holders: [Int: Int] {
        var found: [Int: Int] = [:]
        for seat in 0..<max(1, game.playerCount) where seat != slot {
            guard game.colorIndices.indices.contains(seat) else { continue }
            found[game.colorIndices[seat]] = seat
        }
        return found
    }

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // Close in the corner, like every other surface: a pick
                    // applies immediately, so Done had nothing to confirm.
                    retroLeaveRow(retroClose(dismiss)).padding(.horizontal, -16)
                    RetroTitle(Text("Player \(slot + 1) color", bundle: .module))
                    palettePanel
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var palettePanel: some View {
        VStack(spacing: 10) {
            RetroHeading(Text("PICK A COLOR", bundle: .module))
            // Fixed three-across rather than adaptive: nine colors are three
            // tidy rows on every phone, and an adaptive grid reflowed them into
            // an uneven block that read as an accident.
            LazyVGrid(
                columns: Array(repeating: GridItem(spacing: 10), count: 3), spacing: 10
            ) {
                ForEach(0..<CouchGame.palette.count, id: \.self) { color in
                    chip(color)
                }
            }
            Text("A color another player has is not available.", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .retroPanel()
    }

    private func chip(_ color: Int) -> some View {
        let mine = game.colorIndices.indices.contains(slot) && game.colorIndices[slot] == color
        let holder = holders[color]
        // **Not a disabled Button.** SwiftUI dims a disabled control, and dimming
        // is the one thing a color palette must never do to its colors — the
        // taken chips came back visibly paler than the paint they name, so a
        // player comparing the sheet to the grid saw two different greens.
        // Drawn as a plain view and simply not given a tap instead; the ✕ tile
        // says unavailable, and the model refuses it anyway (`chooseColor`).
        return Group {
            if holder != nil {
                chipFace(color, mine: mine, holder: holder)
            } else {
                Button {
                    game.chooseColor(color, slot: slot)
                    dismiss()
                } label: {
                    chipFace(color, mine: mine, holder: holder)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(Text("Color \(color + 1)", bundle: .module))
        .accessibilityHint(
            holder != nil
                ? Text("Taken", bundle: .module) : Text("Available", bundle: .module))
    }

    private func chipFace(_ color: Int, mine: Bool, holder: Int?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // **The color is never veiled.** A wash over it changes what
                // the color looks like, which is the trap the palette's own
                // notes warn about — the struck-through lime read as a
                // different, murkier green rather than as an unavailable
                // lime. The taken mark goes BESIDE the paint instead: a
                // heavy ✕ on its own opaque tile, so the swatch stays true.
                Rectangle()
                    .fill(CouchGame.palette[color])
                    .frame(height: 44)
                    .overlay(RetroBevel(inset: mine, thickness: 2))
                if holder != nil {
                    Text(verbatim: "✕")
                        .font(Retro.font(15, weight: .black))
                        .foregroundStyle(Retro.ink)
                        .frame(width: 26, height: 26)
                        .background(Retro.panel)
                        .overlay(RetroBevel(inset: true, thickness: 2))
                }
                if mine {
                    Text(verbatim: "▸")
                        .font(Retro.font(15, weight: .black))
                        .foregroundStyle(Retro.ink)
                        .frame(width: 26, height: 26)
                        .background(Retro.amber)
                        .overlay(RetroBevel(thickness: 2))
                }
            }
            // Whose it is, or nothing. A fixed height rather than a space
            // character: an empty Text still lays out by its font, so the
            // labelled chip's row grew taller than its neighbours.
            Text(verbatim: holder.map { game.displayName(forSeat: $0) } ?? "")
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 14)
        }
    }
}
