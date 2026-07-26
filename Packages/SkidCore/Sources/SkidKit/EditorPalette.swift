import SkidCore
import SwiftUI

/// What the editor palette offers, and how it's organised.
///
/// **The shape of this is deliberate.** The catalog is a cross-product — every
/// shape × every radius × both handednesses — and listing it produced ten
/// buttons per radius tab that multiplied with every family added. But building a
/// track isn't really a choice among forty pieces; almost every move is "go left,
/// go straight, or go right", with the corner's angle and radius changing only
/// occasionally.
///
/// So the palette is three fixed buttons — **left corner / straight / right
/// corner** — fed by shared selectors for angle, radius and straight length. The
/// left and right buttons are visibly the same corner mirrored, which is what
/// makes them read as a pair. Everything that isn't part of that triple (hairpins,
/// chicanes, jogs, ramps) is a **one-off**, and one-offs live on an assignable
/// hotbar instead: still one tap to place, and it doesn't grow when the catalog
/// does.
/// A one-off family that has a variant per radius, so a hotbar slot holding it
/// can follow the corner radius you're building with.
///
/// Only **chicane** has all three; **hairpin** has no sweep variant (the design
/// doc argues against one), and **jog** isn't a radius family at all — 240 and
/// 360 name a *lateral shift*, and both use a tight first arc. So a slot follows
/// the radius when its family has that variant and keeps its own otherwise,
/// rather than pretending every one-off has three sizes.
enum CurveAngle: String, CaseIterable, Identifiable {
    case degrees45, degrees90
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .degrees45: return "45°"
        case .degrees90: return "90°"
        }
    }
}

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

enum StraightLength: String, CaseIterable, Identifiable {
    case short, standard, long
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .short: return "Short"
        case .standard: return "2U"
        case .long: return "Long"
        }
    }

    var piece: PieceID {
        switch self {
        case .short: return PieceCatalog.ID.shortStraight
        case .standard: return PieceCatalog.ID.straight
        case .long: return PieceCatalog.ID.longStraight
        }
    }
}

/// A one-off family with a variant per radius, so a hotbar slot holding it can
/// follow the corner radius you are building with.
///
/// Only **chicane** has all three radii; **hairpin** has no sweep variant, and
/// **jog** is not a radius family at all — 240/360 name a lateral shift and both
/// use a tight first arc. So a slot follows the radius where its family has that
/// variant and keeps its own otherwise.
enum OneOffFamily {
    case hairpin, chicane

    func piece(left: Bool, radius: CurveRadius) -> PieceID? {
        typealias Pieces = PieceCatalog.ID
        switch (self, radius) {
        case (.hairpin, .tight):
            return left ? Pieces.hairpinTightLeft : Pieces.hairpinTightRight
        case (.hairpin, .medium):
            return left ? Pieces.hairpinMediumLeft : Pieces.hairpinMediumRight
        case (.hairpin, .sweep):
            return nil  // no sweep hairpin in the catalog
        case (.chicane, .tight):
            return left ? Pieces.chicaneTightLeft : Pieces.chicaneTightRight
        case (.chicane, .medium):
            return left ? Pieces.chicaneMediumLeft : Pieces.chicaneMediumRight
        case (.chicane, .sweep):
            return left ? Pieces.chicaneSweepLeft : Pieces.chicaneSweepRight
        }
    }
}

extension EditorView {
    /// The angle of the corner the left/right buttons build.

    /// The three catalog radii — how tight the corner the left/right buttons build.

    /// The length of the straight the middle button builds.

    /// The corner a button places: its own handedness and angle, at the shared
    /// radius.
    ///
    /// Angle is a parameter rather than a setting because it's a button *position*
    /// now — 45L · 90L · 90R · 45R, mirrored around the centre — so both angles are
    /// always one tap away and nothing has to be toggled.
    func corner(left: Bool, angle: CurveAngle, radius: CurveRadius) -> PieceID {
        typealias Pieces = PieceCatalog.ID
        switch (angle, radius) {
        case (.degrees45, .tight): return left ? Pieces.curve45TightLeft : Pieces.curve45TightRight
        case (.degrees45, .medium):
            return left ? Pieces.curve45MediumLeft : Pieces.curve45MediumRight
        case (.degrees45, .sweep): return left ? Pieces.curve45SweepLeft : Pieces.curve45SweepRight
        case (.degrees90, .tight): return left ? Pieces.curve90TightLeft : Pieces.curve90TightRight
        case (.degrees90, .medium):
            return left ? Pieces.curve90MediumLeft : Pieces.curve90MediumRight
        case (.degrees90, .sweep): return left ? Pieces.curve90SweepLeft : Pieces.curve90SweepRight
        }
    }

    /// The straight the middle button places, at the current length.
    var straight: PieceID { straightLength.piece }

    /// Which family and handedness a piece belongs to, if it's one that tracks the
    /// radius. Nil for pieces that don't (jogs, the ramp).
    static func family(of piece: PieceID) -> (family: OneOffFamily, left: Bool)? {
        typealias Pieces = PieceCatalog.ID
        switch piece {
        case Pieces.hairpinTightLeft, Pieces.hairpinMediumLeft: return (.hairpin, true)
        case Pieces.hairpinTightRight, Pieces.hairpinMediumRight: return (.hairpin, false)
        case Pieces.chicaneTightLeft, Pieces.chicaneMediumLeft, Pieces.chicaneSweepLeft:
            return (.chicane, true)
        case Pieces.chicaneTightRight, Pieces.chicaneMediumRight, Pieces.chicaneSweepRight:
            return (.chicane, false)
        default: return nil
        }
    }

    /// One-off pieces: everything that isn't "left / straight / right".
    ///
    /// These are the hotbar's contents, and the full list a long-press offers.
    /// Crossings, jumps and forks are **absent on purpose** — the catalog has
    /// their geometry but the Phase-A compiler can't build them, so placing one
    /// could only ever produce a track that fails to compile. They join this list
    /// with the compiler work (see docs/track-pieces.md "Beyond the ring").
    static var oneOffPieces: [PieceID] {
        typealias Pieces = PieceCatalog.ID
        return [
            Pieces.hairpinTightLeft, Pieces.hairpinTightRight,
            Pieces.hairpinMediumLeft, Pieces.hairpinMediumRight,
            Pieces.chicaneTightLeft, Pieces.chicaneTightRight,
            Pieces.chicaneMediumLeft, Pieces.chicaneMediumRight,
            Pieces.chicaneSweepLeft, Pieces.chicaneSweepRight,
            Pieces.jog240Left, Pieces.jog240Right,
            Pieces.jog360Left, Pieces.jog360Right,
            HotbarSlot.rampSentinel,
        ]
    }

    /// A hotbar slot's contents: a catalog piece, or the context-aware ramp.
    enum HotbarSlot {
        /// Not a real catalog id — "the ramp that knows which way to go", resolved
        /// on tap (up from the ground, down from the deck). Negative so it can
        /// never collide with a real `PieceID`.
        static let rampSentinel: PieceID = -1

        /// What the hotbar holds on a fresh install: both hairpins, both medium
        /// chicanes, and the ramp — the one-offs a track most often wants.
        static let defaults: [PieceID] = [
            PieceCatalog.ID.hairpinMediumLeft, PieceCatalog.ID.hairpinMediumRight,
            PieceCatalog.ID.chicaneMediumLeft, PieceCatalog.ID.chicaneMediumRight,
            rampSentinel,
        ]

        static let count = 5
    }

    /// A short label for any piece, for the hotbar's picker.
    ///
    /// A table rather than a switch: one arm per piece tripped the complexity
    /// limit, and a lookup reads better for what is simply a name list.
    static func pieceLabel(_ id: PieceID) -> LocalizedStringKey {
        pieceLabels[id] ?? "Piece"
    }

    private static let pieceLabels: [PieceID: LocalizedStringKey] = [
        HotbarSlot.rampSentinel: "Ramp",
        PieceCatalog.ID.hairpinTightLeft: "Hairpin L (tight)",
        PieceCatalog.ID.hairpinTightRight: "Hairpin R (tight)",
        PieceCatalog.ID.hairpinMediumLeft: "Hairpin L",
        PieceCatalog.ID.hairpinMediumRight: "Hairpin R",
        PieceCatalog.ID.chicaneTightLeft: "Chicane L (tight)",
        PieceCatalog.ID.chicaneTightRight: "Chicane R (tight)",
        PieceCatalog.ID.chicaneMediumLeft: "Chicane L",
        PieceCatalog.ID.chicaneMediumRight: "Chicane R",
        PieceCatalog.ID.chicaneSweepLeft: "Chicane L (sweep)",
        PieceCatalog.ID.chicaneSweepRight: "Chicane R (sweep)",
        PieceCatalog.ID.jog240Left: "Jog L",
        PieceCatalog.ID.jog240Right: "Jog R",
        PieceCatalog.ID.jog360Left: "Jog L (wide)",
        PieceCatalog.ID.jog360Right: "Jog R (wide)",
    ]
}
