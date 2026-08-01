import XCTest

@testable import SkidCore

/// **The same loop decorates the same way however it is spelled.** A closed ring
/// can be written starting from any of its pieces; kerbs are a fact about the
/// road's shape, so every spelling must paint the same stretches.
///
/// It didn't hold: corner grouping walked the list linearly, so a turn straddling
/// the seam was cut into two corners — each with its own apex and its own exit
/// run. Reported from device as kerbs "resetting" on a copy/paste, because the
/// editor holds a ring in build order while copying normalizes it.
final class KerbSpellingTests: XCTestCase {
    /// Every kerbed edge point, in WORLD space — the spelling-independent view.
    private func kerbedPoints(_ layout: TrackLayout) -> Set<String> {
        let walk = layout.walk()
        let plan = KerbPlan.plan(for: walk)
        var points: Set<String> = []
        for (index, placed) in walk.placed.enumerated() {
            let samples = placed.centerlineSamples(
                degreesPerSample: KerbPlan.degreesPerSample)
            for (sample, point) in samples.enumerated() {
                let style = plan.style(piece: index, sample: sample)
                let key = "\(Int(point.x.rounded()))|\(Int(point.y.rounded()))"
                if style.left == .kerb { points.insert("L" + key) }
                if style.right == .kerb { points.insert("R" + key) }
            }
        }
        return points
    }

    private func assertSpellingIndependent(_ code: String, _ name: String) throws {
        let canonical = try TrackCode.decode(code)
        let expected = kerbedPoints(canonical)
        XCTAssertFalse(expected.isEmpty, "\(name): fixture has no kerbs to compare")
        for offset in 1..<canonical.pieces.count {
            var spelled = canonical
            spelled.rotate(to: offset)
            // Rotation declines on anything that isn't a closed ring.
            guard spelled.pieces != canonical.pieces else { continue }
            let actual = kerbedPoints(spelled)
            XCTAssertEqual(
                actual, expected,
                """
                \(name) spelled from \(offset) kerbs differently \
                (\(actual.subtracting(expected).count) extra, \
                \(expected.subtracting(actual).count) missing)
                """)
        }
    }

    /// The flat eight — the reported case. 13 of its 16 rotations disagreed.
    func testTheFlatEightDecoratesTheSameHoweverItIsSpelled() throws {
        try assertSpellingIndependent("AWoBDh8KDBEFeQUFFXoGBHgEAgIADAMFB4AFoAA", "flat eight")
    }

    /// And the built-ins, which cover corners of every radius plus elevation.
    func testTheBuiltInsDecorateTheSameHoweverTheyAreSpelled() throws {
        for builtin in TrackLibrary.builtins {
            try assertSpellingIndependent(builtin.code, builtin.name)
        }
    }
}
