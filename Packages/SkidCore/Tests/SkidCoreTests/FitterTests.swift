import XCTest

@testable import SkidCore

/// The fitting piece's geometry and solve. See docs/flexible-tracks-plan.md.
final class FitterTests: XCTestCase {
    private let unit = Double(PieceCatalog.unit)

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
    /// The answer is a pair of 45° arcs with no straight between them (R=1U). Note
    /// the planning notes quoted "R=1U, 29.28°, 1.172U" for this gap — that solves
    /// a *different* target (forward 240, left 99.4), because the search that found
    /// it was fed `(2.0, −0.828)` in units where the real gap is `(1.414, −0.586)`.
    /// The exact solve, being exact, finds the shorter true answer.
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
        XCTAssertEqual(step.forward, forward, accuracy: 1e-9)
        XCTAssertEqual(step.left, left, accuracy: 1e-9)
    }

    /// The gap my planning search actually solved, kept because it exercises a
    /// non-zero straight between the arcs — the general case.
    func testAGapNeedingAStraightBetweenTheArcs() throws {
        let fitter = try XCTUnwrap(
            Fitter.solving(forward: 4 * unit, left: -1.5 * unit))
        XCTAssertGreaterThan(fitter.length, 0, "this one needs a middle straight")
        let step = fitter.displacement
        XCTAssertEqual(step.forward, 4 * unit, accuracy: 1e-6)
        XCTAssertEqual(step.left, -1.5 * unit, accuracy: 1e-6)
    }

    /// A purely forward gap solves as the zero-angle straight — the case that
    /// makes the piece total.
    func testAForwardOnlyGapSolvesAsAStraight() throws {
        for units in [0.5, 2.0, 5.0] {
            let fitter = try XCTUnwrap(
                Fitter.solving(forward: units * unit, left: 0),
                "\(units)U straight-ahead must solve")
            XCTAssertEqual(fitter.angle, 0, accuracy: 1e-9)
            XCTAssertEqual(fitter.length, units * unit, accuracy: 1e-6)
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
                    step.forward, forward, accuracy: 1e-6,
                    "forward \(forward) left \(left)")
                XCTAssertEqual(
                    step.left, left, accuracy: 1e-6, "forward \(forward) left \(left)")
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

    /// Displacement matches the closed form worked out by hand: two arc chords
    /// plus the straight, resolved into the entry frame.
    func testDisplacementMatchesTheClosedForm() {
        let radius = 2 * unit
        let angle = 29.28 * .pi / 180
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
