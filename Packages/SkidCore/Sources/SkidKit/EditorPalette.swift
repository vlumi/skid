import SkidCore
import SwiftUI

/// The editor palette's contents: which tabs exist, which radius the Curves row
/// is tuned to, and the pieces each tab shows. Split out of `EditorView` to
/// keep both files inside the length budget — and because this is the part that
/// grows as catalog families land (decals, decorations).
extension EditorView {
    enum PaletteTab: String, CaseIterable, Identifiable {
        case straights, curves, elevation
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .straights: return "Straights"
            case .curves: return "Curves"
            case .elevation: return "Elevation"
            }
        }
    }

    /// The three catalog radii, as a picker dimension for the Curves tab.
    enum CurveRadius: String, CaseIterable, Identifiable {
        case tight, medium, sweep
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .tight: return "Tight"
            case .medium: return "Medium"
            case .sweep: return "Sweep"
            }
        }
    }

    struct PaletteItem: Identifiable {
        let id: PieceID
        let label: LocalizedStringKey
        /// A sentinel id meaning "the context-aware ramp" (up from ground,
        /// down from the deck) — resolved to a real piece id on tap.
        static let rampSentinel = -1
    }

    /// The pieces on show, for the current tab (and radius, in Curves).
    /// Curves covers everything that bends — plain corners, hairpins, and the
    /// S families (chicane and lane jog) — since those are curves too.
    var visiblePieces: [PaletteItem] {
        switch tab {
        case .straights:
            return [
                .init(id: PieceCatalog.ID.shortStraight, label: "Short"),
                .init(id: PieceCatalog.ID.straight, label: "Straight"),
                .init(id: PieceCatalog.ID.longStraight, label: "Long"),
            ]
        case .curves:
            return curvePieces
        case .elevation:
            // "Ramp" is a single button: with only two elevations it picks up
            // from the ground and down from the deck automatically (see
            // `game.editorRamp`).
            //
            // Crossings and jumps are NOT offered yet: the catalog has their
            // geometry, but the Phase-A compiler doesn't handle either kind
            // (a track containing one fails to compile), so placing them could
            // only ever build something broken. They return with the compiler
            // work — see docs/track-pieces.md "Beyond the ring".
            return [.init(id: PaletteItem.rampSentinel, label: "Ramp")]
        }
    }

    /// Curves at the selected radius: 45°, 90°, chicane — plus the hairpin and
    /// lane jog at the radii that have them (no sweep hairpin; jogs are the
    /// two fixed radius-bridging shifts).
    var curvePieces: [PaletteItem] {
        var items: [PaletteItem] = []
        switch radius {
        case .tight:
            items += [
                .init(id: PieceCatalog.ID.curve45TightLeft, label: "Left 45"),
                .init(id: PieceCatalog.ID.curve45TightRight, label: "Right 45"),
                .init(id: PieceCatalog.ID.curve90TightLeft, label: "Left 90"),
                .init(id: PieceCatalog.ID.curve90TightRight, label: "Right 90"),
                .init(id: PieceCatalog.ID.hairpinTightLeft, label: "Hairpin L"),
                .init(id: PieceCatalog.ID.hairpinTightRight, label: "Hairpin R"),
                .init(id: PieceCatalog.ID.chicaneTightLeft, label: "Chicane L"),
                .init(id: PieceCatalog.ID.chicaneTightRight, label: "Chicane R"),
                .init(id: PieceCatalog.ID.jog240Left, label: "Jog L"),
                .init(id: PieceCatalog.ID.jog240Right, label: "Jog R"),
            ]
        case .medium:
            items += [
                .init(id: PieceCatalog.ID.curve45MediumLeft, label: "Left 45"),
                .init(id: PieceCatalog.ID.curve45MediumRight, label: "Right 45"),
                .init(id: PieceCatalog.ID.curve90MediumLeft, label: "Left 90"),
                .init(id: PieceCatalog.ID.curve90MediumRight, label: "Right 90"),
                .init(id: PieceCatalog.ID.hairpinMediumLeft, label: "Hairpin L"),
                .init(id: PieceCatalog.ID.hairpinMediumRight, label: "Hairpin R"),
                .init(id: PieceCatalog.ID.chicaneMediumLeft, label: "Chicane L"),
                .init(id: PieceCatalog.ID.chicaneMediumRight, label: "Chicane R"),
                .init(id: PieceCatalog.ID.jog360Left, label: "Jog L"),
                .init(id: PieceCatalog.ID.jog360Right, label: "Jog R"),
            ]
        case .sweep:
            items += [
                .init(id: PieceCatalog.ID.curve45SweepLeft, label: "Left 45"),
                .init(id: PieceCatalog.ID.curve45SweepRight, label: "Right 45"),
                .init(id: PieceCatalog.ID.curve90SweepLeft, label: "Left 90"),
                .init(id: PieceCatalog.ID.curve90SweepRight, label: "Right 90"),
                .init(id: PieceCatalog.ID.chicaneSweepLeft, label: "Chicane L"),
                .init(id: PieceCatalog.ID.chicaneSweepRight, label: "Chicane R"),
            ]
        }
        return items
    }

    /// Whether this palette entry can be placed on the current loose end. The
    /// ramp button resolves to whichever ramp direction applies.
    func canPlace(_ item: PaletteItem) -> Bool {
        guard let layout = game.editorLayout else { return false }
        let id: PieceID
        if item.id == PaletteItem.rampSentinel {
            let elevated = (layout.walk().placed.last?.exitHeight ?? 0) > 0.5
            id = elevated ? PieceCatalog.ID.rampDown : PieceCatalog.ID.rampUp
        } else {
            id = item.id
        }
        return game.editorCanAppend(id)
    }

    /// The scrollable row of piece buttons for the current tab. Each icon
    /// renders the piece as it will land on the selected loose end (rotated to
    /// its heading, in the deck look when building elevated).
    func pieceRow(walk: WalkResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visiblePieces) { item in
                    // A piece that would pave over the track or run off the
                    // canvas is DISABLED — being blocked beats placing it and
                    // then reading a warning that's easy to miss.
                    let placeable = canPlace(item)
                    Button {
                        if item.id == PaletteItem.rampSentinel {
                            game.editorRamp()
                        } else {
                            game.editorAppend(item.id)
                        }
                    } label: {
                        PieceIcon(
                            id: item.id, entryHeading: appendHeading(walk),
                            entryHeight: appendHeight(walk)
                        )
                        .frame(width: 56, height: 56)
                        .background(
                            Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12)
                        )
                        .opacity(placeable ? 1 : 0.25)
                        .accessibilityLabel(Text(item.label, bundle: .module))
                    }
                    .disabled(!placeable)
                }
            }
            .padding(.horizontal)
        }
    }
}
