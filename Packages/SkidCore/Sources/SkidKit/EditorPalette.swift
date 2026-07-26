import SkidCore
import SwiftUI

/// What the editor palette offers, and how it's organised.
///
/// **The building vocabulary is the primitive set.** A layout holds primitives — a
/// short straight and 45° corners at three radii — so that is what the main row
/// offers. Every larger shape is something you build: a 90° is two 45s, a hairpin
/// four, a 2U straight two shorts.
///
/// That wasn't the first design. The main row used to offer the whole catalog as a
/// cross-product (every shape × radius × handedness, ten buttons per radius tab),
/// then a curated set of compounds with 90° buttons alongside the 45s. Both were
/// answers to a question that went away: once you can compose shapes exactly, a
/// hairpin button isn't a *shape* you need, it's four taps saved — and it cost a
/// row that grew with the catalog, plus a mismatch where one tap took four presses
/// to undo.
///
/// What's left on the main row is the corners and the straight, which is the whole
/// building vocabulary; anything that isn't part of it lives on the assignable
/// hotbar below (see `HotbarSlot`). Compounds still exist, but only where they pay
/// for themselves and nobody has to see them: **one byte** in a share code
/// (`PiecePacking`) and **one step** in the closure search (`ClosureSearch`).
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

extension EditorView {
    /// The 45° corner a button places: its own handedness, at the shared radius.
    ///
    /// 45° is not a choice — it's the only primitive corner. Radius is, which is
    /// why it's the carousel axis.
    func corner(left: Bool, radius: CurveRadius) -> PieceID {
        typealias Pieces = PieceCatalog.ID
        switch radius {
        case .tight: return left ? Pieces.curve45TightLeft : Pieces.curve45TightRight
        case .medium: return left ? Pieces.curve45MediumLeft : Pieces.curve45MediumRight
        case .sweep: return left ? Pieces.curve45SweepLeft : Pieces.curve45SweepRight
        }
    }

    /// The straight the middle button places. One length, because one is primitive.
    var straight: PieceID { PieceCatalog.ID.shortStraight }

    /// The hotbar: assignable slots for the pieces that aren't "corner or
    /// straight".
    ///
    /// Separate from the primitives question on purpose. The corner/straight
    /// vocabulary is fixed and lives on the main row; the hotbar is for everything
    /// *else*, and that set is about to grow — jumps, gaps and landings, then
    /// decorations — none of which is a compound. Keeping it assignable is what
    /// stops the palette growing a button per catalog family again.
    enum HotbarSlot {
        /// Not a real catalog id — "the ramp that knows which way to go", resolved
        /// on tap (up from the ground, down from the deck). Negative so it can
        /// never collide with a real `PieceID`.
        static let rampSentinel: PieceID = -1

        /// What the hotbar holds on a fresh install. Only the ramp exists to put
        /// here today; the remaining slots stay empty rather than being padded with
        /// something arbitrary, and they fill in as pieces land.
        static let defaults: [PieceID] = [rampSentinel]

        /// An empty slot — draws as a placeholder and places nothing.
        static let empty: PieceID = -2

        static let count = 5
    }

    /// Everything the hotbar can hold: the pieces that aren't part of the
    /// corner/straight vocabulary.
    ///
    /// Jumps, gaps, landings and decorations join this list as they land — the
    /// catalog already carries some of that geometry, but the Phase-A compiler
    /// can't build it, so offering it would only produce tracks that fail to
    /// compile (see docs/track-pieces.md "Beyond the ring").
    static var hotbarPieces: [PieceID] {
        [HotbarSlot.rampSentinel]
    }

    /// A short label for any piece the palette can show.
    static func pieceLabel(_ id: PieceID) -> LocalizedStringKey {
        pieceLabels[id] ?? "Piece"
    }

    private static let pieceLabels: [PieceID: LocalizedStringKey] = [
        HotbarSlot.rampSentinel: "Ramp",
        HotbarSlot.empty: "Empty slot",
        PieceCatalog.ID.shortStraight: "Straight",
        PieceCatalog.ID.curve45TightLeft: "Left (tight)",
        PieceCatalog.ID.curve45TightRight: "Right (tight)",
        PieceCatalog.ID.curve45MediumLeft: "Left",
        PieceCatalog.ID.curve45MediumRight: "Right",
        PieceCatalog.ID.curve45SweepLeft: "Left (sweep)",
        PieceCatalog.ID.curve45SweepRight: "Right (sweep)",
        PieceCatalog.ID.rampUp: "Ramp up",
        PieceCatalog.ID.rampDown: "Ramp down",
    ]
}
