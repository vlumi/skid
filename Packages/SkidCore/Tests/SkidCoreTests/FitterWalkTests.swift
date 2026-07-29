import XCTest

@testable import SkidCore

/// Placing a fitter in a layout: it closes a ring the catalog cannot.
final class FitterWalkTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID
    private let unit = Double(PieceCatalog.unit)

    /// **A fitter's exit is the pose it closes onto, exactly.** That is what keeps
    /// the pose graph in `Coord`'s exact ring while the fitter's own shape is
    /// float: nothing irrational is ever stored as a position.
    func testAFitterTakesItsExitFromTheInletItCloses() throws {
        // A chain that comes back round to the origin's heading but stops short
        // of its position — the gap a fitter exists to bridge. Four right turns
        // return the heading to where it started.
        let pieces: [PieceID] = [
            Catalog.startGrid, Catalog.curve90MediumRight, Catalog.curve90MediumRight,
            Catalog.curve90MediumRight, Catalog.curve90MediumRight, Catalog.fitter,
        ]
        var layout = TrackLayout(pieces: pieces, gateSeams: [0])
        // Solve the fitter for whatever gap the chain leaves. The walk resolves the
        // exit itself, so any plausible shape suffices for this assertion.
        layout.fitters = [5: Fitter(radius: unit, angle: 0, length: unit, stepsLeft: true)]
        let walk = layout.walk()
        let fitter = try XCTUnwrap(walk.placed.last)
        XCTAssertEqual(fitter.id, Catalog.fitter)
        // Its exit is an EXACT pose — the origin it closed onto.
        XCTAssertEqual(
            fitter.exits[0].position, layout.origin.position,
            "the fitter's exit must be the inlet's own exact pose")
        XCTAssertEqual(fitter.exits[0].heading, layout.origin.heading)
    }

    /// The walk still refuses a fitter with nothing to close onto, rather than
    /// inventing a destination.
    func testAFitterWithNothingToCloseOntoFails() {
        // The origin inlet faces INTO the first piece, so a fitter placed while
        // heading the wrong way has no same-heading inlet to reach.
        let layout = TrackLayout(
            pieces: [Catalog.startGrid, Catalog.curve90MediumRight, Catalog.fitter],
            gateSeams: [0])
        let walk = layout.walk()
        XCTAssertNotNil(walk.failure, "a fitter needs an inlet to close onto")
    }

    /// A track with no fitter walks exactly as before — the placeholder catalog
    /// entry must not change anything.
    func testOrdinaryTracksAreUnaffected() throws {
        for builtin in TrackLibrary.builtins {
            let layout = try TrackCode.decode(builtin.code)
            let walk = layout.walk()
            XCTAssertNil(walk.failure, "\(builtin.id) must still walk")
            XCTAssertTrue(walk.openEnds.isEmpty, "\(builtin.id) must still close")
        }
    }
}
