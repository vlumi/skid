import SkidCore
import SwiftUI

/// The editor palette's contents: which tabs exist, which radius the Curves row
/// is tuned to, and the pieces each tab shows. Split out of `EditorView` to
/// keep both files inside the length budget — and because this is the part that
/// grows as catalog families land (decals, decorations).
extension EditorView {
    enum PaletteTab: String, CaseIterable, Identifiable {
        case straights, curves, special
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .straights: return "Straights"
            case .curves: return "Curves"
            case .special: return "Special"
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
        case .special:
            // "Ramp" is a single button: with only two elevations it picks up
            // from the ground and down from the deck automatically (see
            // `game.editorRamp`).
            return [
                .init(id: PaletteItem.rampSentinel, label: "Ramp"),
                .init(id: PieceCatalog.ID.crossing, label: "Crossing"),
                .init(id: PieceCatalog.ID.jump, label: "Jump"),
            ]
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

    /// The scrollable row of piece buttons for the current tab. Each icon
    /// renders the piece as it will land on the selected loose end (rotated to
    /// its heading, in the deck look when building elevated).
    func pieceRow(walk: WalkResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visiblePieces) { item in
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
                        .accessibilityLabel(Text(item.label, bundle: .module))
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
