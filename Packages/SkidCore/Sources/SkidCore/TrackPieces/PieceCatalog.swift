import Foundation

/// The piece catalog: the id → `Piece` table. Ids in the one-byte range
/// (0…127) are **core geometry**; decals and other variants live at 128+ so
/// the compact range is never rationed. The registry is frozen only at the
/// format's first public release — until then ids may be reshuffled.
///
/// Numbers here (lengths, radii, width) are v1 values, expected to be tuned on
/// device once the editor renders them.
public enum PieceCatalog {
    /// One global road width in v1, so every port mates trivially.
    public static let width = 120

    /// Radii used by the curve families.
    public static let tightRadius = 60
    public static let sweepRadius = 160

    /// The whole v1 catalog, keyed by id.
    public static let all: [PieceID: Piece] = {
        var c: [PieceID: Piece] = [:]
        func add(_ p: Piece) { c[p.id] = p }

        // 0–2 straights
        add(Piece(id: 0, paths: [.straight(length: 150)]))
        add(Piece(id: 1, paths: [.straight(length: 300)]))
        add(Piece(id: 2, paths: [.straight(length: 600)]))

        // Curves: the model's `left` is a math-CCW turn, which renders CLOCKWISE
        // on screen (y-down). So a piece the PLAYER calls "left" (screen-left =
        // counter-clockwise on screen) is `left: false` here. `screenLeft`
        // names it once so the catalog reads in player terms.
        let screenLeft = false, screenRight = true

        // 3–6 curve 45° · L/R × tight/sweep
        add(Piece(id: 3, paths: [.arc(radius: tightRadius, eighths: 1, left: screenLeft)]))
        add(Piece(id: 4, paths: [.arc(radius: tightRadius, eighths: 1, left: screenRight)]))
        add(Piece(id: 5, paths: [.arc(radius: sweepRadius, eighths: 1, left: screenLeft)]))
        add(Piece(id: 6, paths: [.arc(radius: sweepRadius, eighths: 1, left: screenRight)]))

        // 7–10 curve 90° · L/R × tight/sweep
        add(Piece(id: 7, paths: [.arc(radius: tightRadius, eighths: 2, left: screenLeft)]))
        add(Piece(id: 8, paths: [.arc(radius: tightRadius, eighths: 2, left: screenRight)]))
        add(Piece(id: 9, paths: [.arc(radius: sweepRadius, eighths: 2, left: screenLeft)]))
        add(Piece(id: 10, paths: [.arc(radius: sweepRadius, eighths: 2, left: screenRight)]))

        // 11–12 hairpin 180° · L/R (tight)
        add(Piece(id: 11, paths: [.arc(radius: tightRadius, eighths: 4, left: screenLeft)]))
        add(Piece(id: 12, paths: [.arc(radius: tightRadius, eighths: 4, left: screenRight)]))

        // 13–14 ramps (straight 300, layer change; up launches)
        add(Piece(id: 13, paths: [.straight(length: 300)], heightDelta: 1, launches: true))
        add(Piece(id: 14, paths: [.straight(length: 300)], heightDelta: -1))

        // 15 start grid (straight 300; the start/finish line is at its exit)
        add(Piece(id: 15, paths: [.straight(length: 300)]))

        // 16–17 crossable straights (at-grade intersections)
        add(Piece(id: 16, kind: .crossing, paths: [.straight(length: 150)]))
        add(Piece(id: 17, kind: .crossing, paths: [.straight(length: 300)]))

        // 18–20 forks: one entry, two exits (straight + branch, or symmetric)
        add(
            Piece(
                id: 18, kind: .fork,
                paths: [.straight(length: 300), .arc(radius: sweepRadius, eighths: 2, left: true)]))
        add(
            Piece(
                id: 19, kind: .fork,
                paths: [
                    .straight(length: 300), .arc(radius: sweepRadius, eighths: 2, left: false),
                ]))
        add(
            Piece(
                id: 20, kind: .fork,
                paths: [
                    .arc(radius: sweepRadius, eighths: 2, left: true),
                    .arc(radius: sweepRadius, eighths: 2, left: false),
                ]))

        // 21–23 joins: mirrored forks (encoded as two entries → one exit). At
        // the model level a join is walked as a fork in reverse; represented
        // here by the same path shapes with `kind: .fork` and a reversed flag
        // handled by the walker. Kept as distinct ids for the directional
        // encoding.
        add(
            Piece(
                id: 21, kind: .fork,
                paths: [.straight(length: 300), .arc(radius: sweepRadius, eighths: 2, left: true)]))
        add(
            Piece(
                id: 22, kind: .fork,
                paths: [
                    .straight(length: 300), .arc(radius: sweepRadius, eighths: 2, left: false),
                ]))
        add(
            Piece(
                id: 23, kind: .fork,
                paths: [
                    .arc(radius: sweepRadius, eighths: 2, left: true),
                    .arc(radius: sweepRadius, eighths: 2, left: false),
                ]))

        // 24 jump (launch lip · gap · landing) — one straight span, launches.
        add(Piece(id: 24, kind: .jump, paths: [.straight(length: 300)], launches: true))

        // 128–130 decal variants: straights with a driving-direction arrow —
        // identical geometry to 0–2, different look (two-byte id range).
        add(Piece(id: 128, paths: [.straight(length: 150)]))
        add(Piece(id: 129, paths: [.straight(length: 300)]))
        add(Piece(id: 130, paths: [.straight(length: 600)]))

        return c
    }()

    /// The start-grid piece id — exactly one per track.
    public static let startPieceID: PieceID = 15

    public static func piece(_ id: PieceID) -> Piece? { all[id] }
}
