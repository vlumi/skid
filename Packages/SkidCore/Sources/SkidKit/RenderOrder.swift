import SkidCore
import SwiftUI

/// **What the world draws, in the order it draws.**
///
/// Everything visible gets a *storey* and a *kind*, and the renderer paints the
/// list sorted by `(storey, kind)`. That is the whole rule: a bridge covers the
/// car beneath it, and a car sits on top of its own road, for the same reason —
/// one comparison, not two special cases.
///
/// This replaced a pair of hardcoded height passes (`-1...0.5`, then `0.75...2`)
/// which forced every drawable to answer "which pass am I in?" separately:
/// ribbons by their maximum height, cars by their body corners over
/// ground-height *road*, marks and gates by their own thresholds. Each new
/// situation added a clause, the clauses disagreed at the edges — a car on the
/// grass under a bridge drew on top of it, because "no road here" and "road
/// above me" gave the same answer — and the passes leaked into the call
/// structure, with the bridge drawn from inside the car-drawing function.
///
/// Storeys, not raw heights: a ramp climbing from 0 to 1 must paint with the
/// ground it leaves, not weave between levels halfway up. Rounding each
/// drawable to the storey it *occupies* keeps a sloped piece whole, and keeps
/// the sort stable when float noise nudges a height.
enum RenderOrder {
    /// Draw order within one storey. Lower paints first.
    ///
    /// Kerbs sit under the road because they are painted straddling its edge
    /// and the asphalt covers their inner half — the sandwich that makes a
    /// kerb and a deck rail land in the same place.
    enum Kind: Int, Comparable, CaseIterable {
        case ground = 0
        case kerb
        case road
        case wall
        case mark
        case gate
        case car
        /// Above every storey: a launched car is between levels by definition.
        case airborne

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    /// One thing to draw, keyed by where it sits in the world.
    struct Layer: Comparable {
        /// The storey this occupies — `Track.level(of:)` of its height.
        var storey: Int
        var kind: Kind
        /// Painted in insertion order within a `(storey, kind)` group, so a
        /// group's internal ordering (walk order for ribbons, player order for
        /// cars) survives the sort.
        var sequence: Int
        var draw: (inout GraphicsContext) -> Void

        static func < (a: Layer, b: Layer) -> Bool {
            (a.storey, a.kind, a.sequence) < (b.storey, b.kind, b.sequence)
        }

        static func == (a: Layer, b: Layer) -> Bool {
            (a.storey, a.kind, a.sequence) == (b.storey, b.kind, b.sequence)
        }
    }

    /// Collects layers, then paints them in order.
    struct Builder {
        private var layers: [Layer] = []
        private var nextSequence = 0

        /// Add a drawable at a world height.
        mutating func add(
            height: Double, kind: Kind, draw: @escaping (inout GraphicsContext) -> Void
        ) {
            add(storey: Track.level(of: height), kind: kind, draw: draw)
        }

        /// Add a drawable at an explicit storey — for things whose storey isn't
        /// a height (the airborne pass, the grass under everything).
        mutating func add(
            storey: Int, kind: Kind, draw: @escaping (inout GraphicsContext) -> Void
        ) {
            layers.append(Layer(storey: storey, kind: kind, sequence: nextSequence, draw: draw))
            nextSequence += 1
        }

        /// Paint everything, lowest storey first.
        func paint(into context: inout GraphicsContext) {
            for layer in layers.sorted() {
                layer.draw(&context)
            }
        }

        /// The paint order as `storey/kind` strings — for tests and debugging,
        /// where the closures themselves can't be compared.
        var debugOrder: [String] {
            layers.sorted().map { "\($0.storey)/\($0.kind)" }
        }

        /// The storeys anything was added at, ascending — what the ribbon pass
        /// needs in order to draw each level's road separately.
        var storeys: [Int] {
            Array(Set(layers.map(\.storey))).sorted()
        }
    }
}
