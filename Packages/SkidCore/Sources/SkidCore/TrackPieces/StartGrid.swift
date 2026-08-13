import Foundation

/// **Where the cars line up.**
///
/// Split out of `PieceCompiler.swift` on the file-length limit, and it earns its own
/// file: the layout is a set of decisions (how many abreast, how rows fill, why cars
/// are staggered within a row) rather than compiler plumbing, and `StartGridTests`
/// tests it directly.
extension PieceCompiler {
    /// Where the four grid slots sit relative to the start/finish line: the
    /// pole `back` behind it, each next slot a further `gap` back, staggered
    /// `lateral` to alternating sides. Shared so the renderer paints its hash
    /// marks exactly where the compiler puts the cars.
    public enum Grid {
        /// How far behind the line the front row sits.
        public static let back = 70.0
        /// Row-to-row spacing. A car is 34 long, so this leaves 16 of air.
        public static let gap = 50.0
        /// Half-span of a **two**-car row: the classic staggered pair.
        public static let lateral = 28.0
        /// Half-span of a **three**-car row. The outer car's edge then sits at
        /// 54 of the road's 60 half-width, leaving 24 units between neighbors —
        /// more than a car's collision diameter.
        public static let wideLateral = 44.0

        /// **The most cars a race can hold.**
        ///
        /// Nine, and neither the grid nor the palette is the binding constraint:
        /// 3 abreast × 3 rows needs 170 of the start piece's 240 units, and the
        /// palette carries nine accessible colors. Four abreast is where geometry
        /// does bite — 9 units of side clearance is under a car's collision
        /// radius, so cars would start the race already touching.
        public static let slots = 9

        /// How many cars stand in each row, front to back, for a field of `count`.
        ///
        /// One rule, the one real grids obey: **a row is never wider than the row
        /// ahead of it**, and the short row goes at the back — so the cars ahead of
        /// you are never fewer than the cars beside you.
        ///
        /// The exception is small fields. Two abreast leaves 68 units between
        /// cars against three abreast's 24, so **while the field fits in two rows
        /// (≤ 4) it stays two abreast**: 4 cars is 2:2, not 3:1, which would
        /// strand the fourth car alone behind a full row — and 4 is the commonest
        /// couch case.
        ///
        ///     1 · 2 · 2:1 · 2:2 · 3:2 · 3:3 · 3:3:1 · 3:3:2 · 3:3:3
        public static func rows(for count: Int) -> [Int] {
            let width = count <= 4 ? 2 : 3
            var rows: [Int] = []
            var left = max(0, count)
            while left > 0 {
                rows.append(min(width, left))
                left -= width
            }
            return rows
        }

        /// How far behind the line the last row sits — the depth of ribbon the
        /// start piece has to provide for a full field.
        public static var depth: Double {
            back + Double(max(0, rows(for: slots).count - 1)) * gap
        }

        /// How much each car within a row sits back from the one beside it.
        ///
        /// **Not decoration — it is what gives the grid an ORDER.** Standings rank by
        /// distance along the centerline, so cars at identical arc positions tie and
        /// the ranking falls back to an index tie-break: on screen, a random order at
        /// the lights. A row of three perfectly abreast produced exactly that (9 cars
        /// scored 3 distinct progress values). Real grids stagger within a row too, so
        /// this is both honest and functional.
        public static let echelon = 14.0

        /// Slot centers, **pole first**, from the line pose. `dir` is the driving
        /// direction; rows run back from the line.
        ///
        /// Within a row cars are spread evenly about the centerline — a 3-row is
        /// left/center/right, a 2-row straddles it — and each is set back slightly
        /// from its neighbor (`echelon`) so no two cars share an arc position.
        public static func positions(line: Vec2, dir: Vec2, count: Int = slots) -> [Vec2] {
            let inward = dir.perpendicular
            var out: [Vec2] = []
            for (row, width) in rows(for: count).enumerated() {
                let rowBack = back + Double(row) * gap
                let half = width >= 3 ? wideLateral : lateral
                for seat in 0..<width {
                    // Evenly spread across the row: a lone car sits on the
                    // centerline, two straddle it, three add a middle.
                    let offset =
                        width == 1
                        ? 0 : (Double(seat) / Double(width - 1) * 2 - 1) * half
                    // …and stepped back across the row, so pole is unambiguous.
                    out.append(
                        line - dir * (rowBack + Double(seat) * echelon) + inward * offset)
                }
            }
            return out
        }
    }
}
