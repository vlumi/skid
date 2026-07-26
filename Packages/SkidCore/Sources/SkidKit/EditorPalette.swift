import SkidCore
import SwiftUI

/// What the editor palette offers, and how it's organised.
///
/// **The palette is the primitive set, and nothing else.** A layout holds
/// primitives — a short straight and 45° corners at three radii — so the palette
/// offers exactly those. Every larger shape is something you build: a 90° is two
/// 45s, a hairpin four, a 2U straight two shorts.
///
/// That wasn't the first design. The palette used to offer the whole catalog as a
/// cross-product (every shape × radius × handedness, ten buttons per radius tab),
/// then a curated set of compounds with 90° buttons and an assignable hotbar of
/// hairpins, chicanes and jogs. Both were answers to a question that went away:
/// once you can compose shapes exactly, a hairpin button isn't a *shape* you need,
/// it's four taps saved — and it cost a palette that grew with the catalog, plus a
/// mismatch where one tap took four presses to undo.
///
/// What's left is one row of corners and one straight, which is the whole
/// vocabulary. Compounds still exist, but only where they pay for themselves and
/// nobody has to see them: **one byte** in a share code (`PiecePacking`) and **one
/// step** in the closure search (`ClosureSearch`).
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

    /// The ramp button's piece id — the one non-corner, non-straight primitive.
    ///
    /// Not a real catalog id: "the ramp that knows which way to go", resolved on tap
    /// (up from the ground, down from the deck). Negative so it can never collide
    /// with a real `PieceID`.
    static let rampSentinel: PieceID = -1

    /// A short label for any piece the palette can show.
    static func pieceLabel(_ id: PieceID) -> LocalizedStringKey {
        pieceLabels[id] ?? "Piece"
    }

    private static let pieceLabels: [PieceID: LocalizedStringKey] = [
        rampSentinel: "Ramp",
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
