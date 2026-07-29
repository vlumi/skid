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

    /// **The drawn road arrives where the exit says it does.** The exit is pinned
    /// to the inlet while the road is sampled from the solved shape, so if the two
    /// disagreed the track would kink at the seam — visibly, and the car would
    /// drive a different line from the one drawn. This is the test that the pinning
    /// trick is sound.
    ///
    /// The case is derived rather than invented: take a ring that closes (the oval
    /// built-in), drop one piece, and the remaining gap is exactly what that piece
    /// spanned. Chains assembled by hand tend to *overshoot* the origin, which a
    /// fitter cannot fix — its length is non-negative, so it can only ever travel
    /// forward.
    func testTheSampledRoadReachesThePinnedExit() throws {
        let full = try TrackCode.decode(
            try XCTUnwrap(TrackLibrary.builtins.first { $0.id == "oval" }).code)
        var short = full
        let dropped = 13  // a 1U straight; the gap becomes 1U straight ahead
        short.pieces.remove(at: dropped)
        short.gateSeams = [0]
        let openWalk = short.walk()
        let end = try XCTUnwrap(openWalk.openEnds.first)
        let delta = short.origin.position.vec2 - end.position.vec2
        let solved = try XCTUnwrap(
            Fitter.solving(
                forward: delta.dot(Vec2(angle: end.heading.radians)),
                left: delta.dot(Vec2(angle: end.heading.radians - .pi / 2))))

        var layout = short
        layout.pieces.append(Catalog.fitter)
        layout.fitters = [layout.pieces.count - 1: solved]
        let closed = layout.walk()
        XCTAssertNil(closed.failure)
        XCTAssertTrue(closed.openEnds.isEmpty, "the fitter must close the ring")

        let placed = try XCTUnwrap(closed.placed.last)
        XCTAssertEqual(placed.id, Catalog.fitter)
        let road = placed.centerlineSamples(degreesPerSample: 3)
        XCTAssertEqual(
            try XCTUnwrap(road.last).distance(to: placed.exits[0].position.vec2), 0,
            accuracy: 0.01,
            "the sampled road must land on the pinned exit, or the seam kinks")
        XCTAssertEqual(
            try XCTUnwrap(road.first).distance(to: placed.entry.position.vec2), 0,
            accuracy: 1e-9, "and start at its entry")
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

/// Validation rules that exist only because a fitter's shape is stored rather
/// than derived.
final class FitterValidationTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    /// A closed ring, with the last piece replaced by a properly solved fitter.
    private func fittedRing() throws -> TrackLayout {
        let full = try TrackCode.decode(
            try XCTUnwrap(TrackLibrary.builtins.first { $0.id == "oval" }).code)
        var short = full
        short.pieces.remove(at: 13)
        short.gateSeams = full.gateSeams.filter { $0 < 13 }
        let end = try XCTUnwrap(short.walk().openEnds.first)
        let delta = short.origin.position.vec2 - end.position.vec2
        let solved = try XCTUnwrap(
            Fitter.solving(
                forward: delta.dot(Vec2(angle: end.heading.radians)),
                left: delta.dot(Vec2(angle: end.heading.radians - .pi / 2))))
        var layout = short
        layout.pieces.append(Catalog.fitter)
        layout.fitters = [layout.pieces.count - 1: solved]
        return layout
    }

    /// **A solved fitter is saveable**, so the rules below aren't just refusing
    /// everything.
    func testARingClosedByAFitterIsSaveable() throws {
        let problems = TrackValidator.validate(try fittedRing()).problems
        XCTAssertFalse(
            problems.contains(.unsolvedFitter(1)),
            "a properly solved fitter must not be reported: \(problems)")
    }

    /// A fitter with no stored shape has no road at all, so the track can't save.
    func testAFitterWithoutAShapeIsRefused() throws {
        var layout = try fittedRing()
        layout.fitters = [:]
        XCTAssertTrue(
            TrackValidator.validate(layout).problems.contains(.unsolvedFitter(1)),
            "an unsolved fitter must be reported")
    }

    /// **A stale shape is refused too** — the case that only exists because the
    /// shape is stored. Editing a neighbour changes the gap without changing the
    /// stored answer, which would leave a kink at the seam.
    func testAStaleFitterShapeIsRefused() throws {
        var layout = try fittedRing()
        let index = layout.pieces.count - 1
        let solved = try XCTUnwrap(layout.fitters[index])
        // Same shape, longer middle: no longer spans the gap it has to.
        layout.fitters[index] = Fitter(
            radius: solved.radius, angle: solved.angle,
            length: solved.length + Double(PieceCatalog.unit), stepsLeft: solved.stepsLeft)
        XCTAssertTrue(
            TrackValidator.validate(layout).problems.contains(.unsolvedFitter(1)),
            "a fitter that no longer reaches its exit must be reported")
    }

    /// An unsolved fitter must not make PLACEMENT illegal — placing the piece and
    /// then solving it is the ordinary order of events.
    func testAnUnsolvedFitterStillPlaces() throws {
        var layout = try fittedRing()
        layout.fitters = [:]
        let problems = TrackValidator.validate(layout).problems
        XCTAssertFalse(
            problems.contains(.overlap), "an unsolved fitter is not an overlap")
    }
}
