import XCTest

@testable import SkidCore

/// Which gate a tap toggles, on the geometry that made three gates
/// unremovable: a whole clover drawn on a small phone.
///
/// Mirrors `EditorView.seam(near:)`'s arithmetic — the view can't be driven
/// from a test, but the rule can.
final class GateTapTests: XCTestCase {
    /// The clover the maintainer built, with gates on the deck.
    private let code = "AUUBGR8PeQMDAR4BDwMDAR4BDwMDAR4BDwMDAR4CBQAIFCAsAwUEOAJYAA"
    /// A whole 1600-unit canvas on a ~750-point screen.
    private let scale: CGFloat = 750.0 / 1600.0
    private let hitRadius: CGFloat = 26

    /// **A tap on a gate's bar removes THAT gate.** The bar is what's drawn and
    /// what the author aims at; measuring to the seam's centre point instead
    /// left a 26-point circle among seams only 56 points apart at this scale —
    /// narrower than a fingertip — so taps landed on a neighbour.
    func testATapAnywhereOnAGateBarPicksThatGate() throws {
        let layout = try TrackCode.decode(code)
        let placed = layout.walk().placed
        for gate in layout.gateSeams where gate != 0 {
            let pose = placed[gate].exits[0]
            let across = Vec2(angle: pose.heading.radians).perpendicular
            // Both ends of the bar and its middle: all must hit this gate.
            for fraction in [-0.45, 0.0, 0.45] {
                let world = pose.position.vec2 + across * (Double(PieceCatalog.width) * fraction)
                let tap = CGPoint(x: world.x * scale, y: world.y * scale)
                XCTAssertEqual(
                    pick(tap, placed: placed, gates: Set(layout.gateSeams)), gate,
                    "a tap at \(fraction) along gate \(gate)'s bar must toggle it")
            }
        }
    }

    /// An empty seam is still reachable: tapping one that carries no gate adds
    /// a gate there rather than snapping to a nearby existing one.
    func testAnEmptySeamIsStillTappable() throws {
        let layout = try TrackCode.decode(code)
        let placed = layout.walk().placed
        let gates = Set(layout.gateSeams)
        // A seam a full piece away from any gate.
        let empty = try XCTUnwrap(
            placed.indices.first { index in
                index != 0 && !gates.contains(index)
                    && layout.gateSeams.allSatisfy { gate in
                        gate == 0
                            || placed[index].exits[0].position.vec2.distance(
                                to: placed[gate].exits[0].position.vec2) > 100
                    }
            })
        let world = placed[empty].exits[0].position.vec2
        let tap = CGPoint(x: world.x * scale, y: world.y * scale)
        XCTAssertEqual(pick(tap, placed: placed, gates: gates), empty)
    }

    /// `EditorView.seam(near:)`'s rule: distance to each drawn gate bar, with
    /// existing gates winning near-ties and height breaking exact ones.
    private func pick(_ tap: CGPoint, placed: [PlacedPiece], gates: Set<Int>) -> Int? {
        var best: Candidate?
        for (index, piece) in placed.enumerated() where index != 0 {
            let distance = barDistance(of: piece, from: tap)
            guard distance < hitRadius else { continue }
            let candidate = Candidate(
                seam: index, distance: distance, height: piece.exitHeight,
                isGate: gates.contains(index))
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.isGate != current.isGate {
                let gate = candidate.isGate ? candidate : current
                let empty = candidate.isGate ? current : candidate
                best = gate.distance < empty.distance + hitRadius / 2 ? gate : empty
            } else if abs(candidate.distance - current.distance) < 1 {
                best = candidate.height > current.height + 0.001 ? candidate : current
            } else if candidate.distance < current.distance {
                best = candidate
            }
        }
        return best?.seam
    }

    /// One seam a tap could have meant.
    private struct Candidate {
        var seam: Int
        var distance: CGFloat
        var height: Double
        var isGate: Bool
    }

    private func barDistance(of piece: PlacedPiece, from tap: CGPoint) -> CGFloat {
        let pose = piece.exits[0]
        let across = Vec2(angle: pose.heading.radians).perpendicular
        let half = across * (Double(PieceCatalog.width) / 2)
        let a = (pose.position.vec2 - half) * Double(scale)
        let b = (pose.position.vec2 + half) * Double(scale)
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return hypot(a.x - tap.x, a.y - tap.y) }
        let t = max(0, min(1, ((tap.x - a.x) * ab.x + (tap.y - a.y) * ab.y) / lengthSquared))
        return hypot(a.x + ab.x * t - tap.x, a.y + ab.y * t - tap.y)
    }
}
