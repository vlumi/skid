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
