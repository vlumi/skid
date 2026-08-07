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
    /// *else*, and that set is about to grow — gaps today, then crossings and
    /// decorations — none of which is a compound. Keeping it assignable is what
    /// stops the palette growing a button per catalog family again.
    enum HotbarSlot {
        /// What the hotbar holds when it appears at all: the Gap. A **default**
        /// rather than merely available, because an empty slot is indistinguishable
        /// from a missing feature — nothing on screen says "assign something here".
        static let defaults: [PieceID] = [PieceCatalog.ID.gap]

        /// An empty slot — draws as a placeholder and places nothing.
        static let empty: PieceID = -2

        /// **As many slots as there are things to put in them**, and no more.
        ///
        /// Fixed at 5 while the row was speculative, which spent a whole strip of
        /// screen on four placeholders — reported from device as cramming the editor
        /// for the sake of one button. The row grows itself as the catalog does, so
        /// there is nothing to remember to bump. `max(1, …)` only guards division;
        /// with nothing to hold, the row is not drawn at all.
        static func count(experimental: Bool) -> Int {
            max(1, EditorView.hotbarPieces(experimental: experimental).count)
        }
    }

    /// Everything the hotbar can hold: the pieces that aren't part of the
    /// corner/straight vocabulary.
    ///
    /// **Gated on the experimental flag**, since today the Gap is the only entry —
    /// see `GameSettings.experimentalGaps` for why the editing of it is the doubtful
    /// part rather than the piece. With the flag off the list is empty, so the whole
    /// row disappears rather than showing a lone dead slot.
    ///
    /// Crossings, forks and decorations join this list as they land — the catalog
    /// already carries some of that geometry, but the Phase-A compiler can't build
    /// it, so offering it would only produce tracks that fail to compile (see
    /// docs/track-pieces.md "Beyond the ring").
    static func hotbarPieces(experimental: Bool) -> [PieceID] {
        experimental ? [PieceCatalog.ID.gap] : []
    }

    /// A short label for any piece the palette can show.
    static func pieceLabel(_ id: PieceID) -> LocalizedStringKey {
        pieceLabels[id] ?? "Piece"
    }

    private static let pieceLabels: [PieceID: LocalizedStringKey] = [
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
        PieceCatalog.ID.gap: "Gap",
    ]
}
