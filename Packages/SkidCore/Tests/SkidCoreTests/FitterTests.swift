import XCTest

@testable import SkidCore

/// The fitting piece's geometry and solve. See docs/flexible-tracks-plan.md.
final class FitterTests: XCTestCase {
    private let unit = Double(PieceCatalog.unit)

    /// How close a solved fitter lands on its target. Not machine epsilon: a
    /// solved fitter is snapped to the encodable grid immediately (so that the
    /// shape which closes the loop is the shape a decoded code reproduces), and
    /// the grid step is ~6e-5 units of length. That is four orders of magnitude
    /// below `Track.surfaceTolerance` and five below a device pixel.
    private let landing = 1e-3

    /// **At zero angle the fitter IS a straight.** Not an edge case to tolerate —
    /// it is what makes the piece total, since a purely longitudinal gap has no
    /// lateral component for a jog to produce.
    func testAZeroAngleFitterIsAPlainStraight() {
        for radius in [unit, 2 * unit, 4 * unit] {
            let fitter = Fitter(radius: radius, angle: 0, length: 3 * unit, stepsLeft: true)
            let step = fitter.displacement
            XCTAssertEqual(step.forward, 3 * unit, accuracy: 1e-9)
            XCTAssertEqual(step.left, 0, accuracy: 1e-9, "no jog at zero angle")
            XCTAssertEqual(
                fitter.arcLength, 3 * unit, accuracy: 1e-9,
                "radius is irrelevant when the arcs vanish")
        }
    }

    /// The jog steps the way it says it does, and mirroring only flips the side.
    func testTheJogStepsToTheStatedSide() {
        let left = Fitter(
            radius: unit, angle: .pi / 6, length: unit, stepsLeft: true
        ).displacement
        let right = Fitter(
            radius: unit, angle: .pi / 6, length: unit, stepsLeft: false
        ).displacement
        XCTAssertGreaterThan(left.left, 0)
        XCTAssertEqual(right.left, -left.left, accuracy: 1e-9)
        XCTAssertEqual(right.forward, left.forward, accuracy: 1e-9)
    }

    /// **The measured mixed-eight gap solves.** This is the acceptance case for
    /// the whole feature: a figure-eight with one axis lobe and one diagonal lobe
    /// leaves `forward = 2·(√2/2)U`, `right = (2−√2)U`, which no catalog piece can
    /// absorb.
    ///
    /// The answer is a pair of 45° arcs with no straight between them, at the tight
    /// radius.
    func testTheMixedEightGapSolves() throws {
        let forward = 2 * (2.0.squareRoot() / 2) * unit
        let left = -(2 - 2.0.squareRoot()) * unit
        let fitter = try XCTUnwrap(Fitter.solving(forward: forward, left: left))
        XCTAssertEqual(fitter.radius, unit, accuracy: 1e-9)
        XCTAssertEqual(fitter.angle * 180 / .pi, 45, accuracy: 0.001)
        // Zero to well within a pixel. The residual (~3e-6 units) is a
        // difference of two nearly-equal large terms — F against 2R·sin 45° —
        // so it cancels down to about 1/300000 of a device pixel, not to a
        // clean zero. Assert at the scale that means something.
        XCTAssertEqual(
            fitter.length / unit, 0, accuracy: 1e-6, "two 45° arcs, no straight")
        XCTAssertFalse(fitter.stepsLeft, "the gap steps right")
        // And it lands where it was asked to, which is the whole point.
        let step = fitter.displacement
        XCTAssertEqual(step.forward, forward, accuracy: landing)
        XCTAssertEqual(step.left, left, accuracy: landing)
    }

    /// A gap needing a straight between the arcs — the general case, where neither
    /// the angle nor the length is degenerate.
    func testAGapNeedingAStraightBetweenTheArcs() throws {
        let fitter = try XCTUnwrap(
            Fitter.solving(forward: 4 * unit, left: -1.5 * unit))
        XCTAssertGreaterThan(fitter.length, 0, "this one needs a middle straight")
        let step = fitter.displacement
        XCTAssertEqual(step.forward, 4 * unit, accuracy: landing)
        XCTAssertEqual(step.left, -1.5 * unit, accuracy: landing)
    }

    /// A purely forward gap solves as the zero-angle straight — the case that
    /// makes the piece total.
    func testAForwardOnlyGapSolvesAsAStraight() throws {
        for units in [0.5, 2.0, 5.0] {
            let fitter = try XCTUnwrap(
                Fitter.solving(forward: units * unit, left: 0),
                "\(units)U straight-ahead must solve")
            XCTAssertEqual(fitter.angle, 0, accuracy: 1e-9)
            XCTAssertEqual(fitter.length, units * unit, accuracy: landing)
        }
    }

    /// **Whatever it returns, it lands exactly on the target.** Swept over a grid
    /// of gaps, since "closes by construction" is the claim the inexact geometry
    /// rests on.
    func testEverySolutionLandsOnItsTarget() {
        var solved = 0
        for forwardHalf in 1...16 {
            for leftHalf in -8...8 {
                let forward = Double(forwardHalf) * 0.5 * unit
                let left = Double(leftHalf) * 0.5 * unit
                guard let fitter = Fitter.solving(forward: forward, left: left)
                else { continue }
                solved += 1
                let step = fitter.displacement
                XCTAssertEqual(
                    step.forward, forward, accuracy: landing,
                    "forward \(forward) left \(left)")
                XCTAssertEqual(
                    step.left, left, accuracy: landing,
                    "forward \(forward) left \(left)")
                XCTAssertGreaterThanOrEqual(fitter.length, 0)
                XCTAssertLessThanOrEqual(fitter.angle, Fitter.maxAngle + 1e-9)
            }
        }
        XCTAssertGreaterThan(solved, 100, "the sweep should solve plenty of gaps")
    }

    /// The dead zone is real and bounded: a gap too short to fit two arcs plus a
    /// straight has no solution, which is what the editor must explain rather
    /// than merely refuse.
    func testGapsTooShortToBridgeHaveNoSolution() {
        XCTAssertNil(Fitter.solving(forward: 0.3 * unit, left: 0.2 * unit))
        XCTAssertNil(Fitter.solving(forward: 0, left: unit), "sideways only")
    }

    /// **A decoded fitter is bit-identical to the one that was solved.** This is
    /// the determinism claim the stored payload exists for: `sin` and `atan2` are
    /// not required to be correctly rounded, so a device that re-solved would risk
    /// an ULP of disagreement, and lockstep has no tolerance for that.
    func testADecodedFitterIsBitIdentical() throws {
        let solved = try XCTUnwrap(
            Fitter.solving(forward: 4 * unit, left: -1.5 * unit))
        let layout = TrackLayout(
            pieces: [PieceCatalog.ID.startGrid, PieceCatalog.ID.fitter],
            gateSeams: [0], fitters: [1: solved])
        let restored = try TrackCode.decode(TrackCode.encode(layout))
        let back = try XCTUnwrap(restored.fitters[1])
        XCTAssertEqual(back.radius.bitPattern, solved.radius.bitPattern)
        XCTAssertEqual(back.angle.bitPattern, solved.angle.bitPattern, "angle must survive exactly")
        XCTAssertEqual(
            back.length.bitPattern, solved.length.bitPattern, "length must survive exactly")
        XCTAssertEqual(back.stepsLeft, solved.stepsLeft)
    }

    /// The whole grid survives encoding, not just one lucky value — swept over
    /// solved fitters across the reachable range.
    func testEverySolvedFitterSurvivesEncodingExactly() throws {
        var checked = 0
        for forwardHalf in 3...12 {
            for leftHalf in [-4, -1, 0, 2, 5] {
                let forward = Double(forwardHalf) * 0.5 * unit
                let left = Double(leftHalf) * 0.5 * unit
                guard let solved = Fitter.solving(forward: forward, left: left)
                else { continue }
                let layout = TrackLayout(
                    pieces: [PieceCatalog.ID.startGrid, PieceCatalog.ID.fitter],
                    gateSeams: [0], fitters: [1: solved])
                let back = try XCTUnwrap(
                    try TrackCode.decode(TrackCode.encode(layout)).fitters[1])
                XCTAssertEqual(back, solved, "forward \(forward) left \(left)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 20, "the sweep should cover plenty")
    }

    /// A track with no fitters encodes exactly as before the section existed —
    /// the section is omitted, so existing codes keep their bytes.
    func testTracksWithoutFittersAreUnaffected() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            XCTAssertTrue(layout.fitters.isEmpty, "\(builtin.id) has no fitters")
            XCTAssertEqual(
                TrackCode.encode(layout), builtin.code,
                "\(builtin.id): adding the fitters section must not change its code")
        }
    }

    /// Malformed fitter payloads are refused rather than misread.
    func testAMalformedFitterSectionIsRejected() throws {
        let solved = try XCTUnwrap(Fitter.solving(forward: 4 * unit, left: -1.5 * unit))
        let layout = TrackLayout(
            pieces: [PieceCatalog.ID.startGrid, PieceCatalog.ID.fitter],
            gateSeams: [0], fitters: [1: solved])
        // A fitter whose index addresses no piece must not decode.
        let bad = TrackLayout(
            pieces: [PieceCatalog.ID.startGrid, PieceCatalog.ID.fitter],
            gateSeams: [0], fitters: [9: solved])
        XCTAssertThrowsError(try TrackCode.decode(TrackCode.encode(bad)))
        // The good one still round-trips, so the guard isn't over-broad.
        XCTAssertNoThrow(try TrackCode.decode(TrackCode.encode(layout)))
    }

    /// Displacement matches the closed form worked out by hand: two arc chords
    /// plus the straight, resolved into the entry frame.
    func testDisplacementMatchesTheClosedForm() {
        let radius = 2 * unit
        let angle = 30 * Double.pi / 180
        let length = 1.172 * unit
        let fitter = Fitter(
            radius: radius, angle: angle, length: length, stepsLeft: false)
        let step = fitter.displacement
        let expectedForward = 2 * radius * sin(angle) + length * cos(angle)
        let expectedLeft = -(2 * radius * (1 - cos(angle)) + length * sin(angle))
        XCTAssertEqual(step.forward, expectedForward, accuracy: 1e-9)
        XCTAssertEqual(step.left, expectedLeft, accuracy: 1e-9)
    }
}
