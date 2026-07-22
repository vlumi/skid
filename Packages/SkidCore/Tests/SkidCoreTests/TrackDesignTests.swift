import XCTest

@testable import SkidCore

final class TrackDesignTests: XCTestCase {
    // MARK: - Fixtures

    /// A plain rounded rectangle: bottom straight driven left→right,
    /// clockwise on screen (the built-ins' winding). All corners filleted.
    private func rectDesign(
        gates: [TrackDesign.GateAnchor]? = nil,
        grid: TrackDesign.StartGrid = TrackDesign.StartGrid(),
        pit: Vec2? = nil
    ) -> TrackDesign {
        TrackDesign(
            id: "test-rect",
            name: "Test Rect",
            size: Vec2(1600, 1000),
            width: 100,
            nodes: [
                .init(id: 1, position: Vec2(300, 800), fillet: 120),
                .init(id: 2, position: Vec2(1300, 800), fillet: 120),
                .init(id: 3, position: Vec2(1300, 200), fillet: 120),
                .init(id: 4, position: Vec2(300, 200), fillet: 120),
            ],
            gates: gates ?? [
                TrackDesign.GateAnchor(node: 2, t: 0.5),
                TrackDesign.GateAnchor(node: 3, t: 0.5),
                TrackDesign.GateAnchor(node: 4, t: 0.5),
                TrackDesign.GateAnchor(node: 1, t: 0.5),
            ],
            grid: grid,
            pit: pit
        )
    }

    /// A flat loop whose top straight carries a bridge span: ground →
    /// rampUp → deck → rampDown → ground, all collinear (fillet 0).
    private func bridgeDesign() -> TrackDesign {
        TrackDesign(
            id: "test-bridge",
            name: "Test Bridge",
            size: Vec2(1600, 1000),
            width: 100,
            nodes: [
                .init(id: 1, position: Vec2(200, 800), fillet: 100),
                .init(id: 2, position: Vec2(1400, 800), fillet: 100),
                .init(id: 3, position: Vec2(1400, 200), fillet: 100),
                .init(id: 4, position: Vec2(1000, 200), edge: .rampUp),
                .init(id: 5, position: Vec2(900, 200), edge: .deck),
                .init(id: 6, position: Vec2(700, 200), edge: .rampDown),
                .init(id: 7, position: Vec2(600, 200)),
                .init(id: 8, position: Vec2(200, 200), fillet: 100),
            ],
            gates: [
                TrackDesign.GateAnchor(node: 5, t: 0.5, span: .deck),
                TrackDesign.GateAnchor(node: 1, t: 0.5),
            ]
        )
    }

    // MARK: - Fillet geometry

    func testRightAngleFilletArcIsExact() throws {
        let track = try rectDesign().compile()
        // Bottom-right corner: node (1300, 800), fillet 120, right turn.
        // Analytic arc center is at (1300 − 120, 800 − 120).
        let center = Vec2(1180, 680)
        let arcPoints = track.centerline.filter { point in
            point.distance(to: Vec2(1300, 800)) < 120 * 1.5
                && point.x >= 1180 - 1e-6 && point.y >= 680 - 1e-6
        }
        XCTAssertGreaterThanOrEqual(arcPoints.count, 16, "a 90° arc gets 16 points at 6°")
        for point in arcPoints {
            XCTAssertEqual(point.distance(to: center), 120, accuracy: 1e-9)
        }
    }

    func testTwoNodeHairpinApproximatesSemicircle() throws {
        // A U-turn is TWO 90° nodes (a single node can't fillet ~180°):
        // tip nodes 2r + 0.01 apart share (almost) one arc center.
        let radius = 50.0
        let design = TrackDesign(
            id: "test-u",
            name: "U",
            size: Vec2(1600, 1000),
            width: 60,
            nodes: [
                .init(id: 1, position: Vec2(100, 100), fillet: 40),
                .init(id: 2, position: Vec2(600, 100), fillet: radius),
                .init(id: 3, position: Vec2(600, 200.01), fillet: radius),
                .init(id: 4, position: Vec2(100, 200.01), fillet: 40),
            ],
            gates: [TrackDesign.GateAnchor(node: 1, t: 0.5, span: .absolute(half: 40))]
        )
        let track = try design.compile()
        let center = Vec2(550, 150.005)  // midpoint between the tips, r inward
        let tipPoints = track.centerline.filter { $0.x > 549 }
        XCTAssertGreaterThanOrEqual(tipPoints.count, 30, "a ~180° tip gets ≥ 30 points")
        for point in tipPoints {
            XCTAssertEqual(point.distance(to: center), radius, accuracy: 0.02)
        }
    }

    func testCurvesStayUnderSixDegreesPerSegment() throws {
        let track = try rectDesign().compile()
        let points = track.centerline
        let count = points.count
        for j in 0..<count {
            let d1 = (points[(j + 1) % count] - points[j]).normalized
            let d2 = (points[(j + 2) % count] - points[(j + 1) % count]).normalized
            let turn = abs(atan2(d1.cross(d2), d1.dot(d2)))
            XCTAssertLessThanOrEqual(turn, Double.pi / 30 + 1e-6)
        }
    }

    // MARK: - Determinism

    func testCompileIsDeterministic() throws {
        XCTAssertEqual(try rectDesign().compile(), try rectDesign().compile())
        XCTAssertEqual(try bridgeDesign().compile(), try bridgeDesign().compile())
    }

    func testCanonicalEncodingIsByteStable() throws {
        let file = TrackDesignFile(design: rectDesign())
        XCTAssertEqual(try file.encoded(), try file.encoded())
        // Round-trip through decode and re-encode: byte-identical.
        let decoded = TrackDesignFile.decode(try file.encoded())
        XCTAssertEqual(try decoded?.encoded(), try file.encoded())
    }

    // MARK: - Codable

    func testDesignRoundTripsThroughJSON() throws {
        let design = bridgeDesign()
        let data = try TrackDesignFile(design: design).encoded()
        XCTAssertEqual(TrackDesignFile.decode(data)?.design, design)
    }

    func testMinimalJSONDecodesWithDefaults() throws {
        let json = """
            {
              "version": 1,
              "design": {
                "id": "mini", "name": "Mini",
                "size": {"x": 800, "y": 600}, "width": 90,
                "nodes": [
                  {"id": 1, "position": {"x": 100, "y": 500}},
                  {"id": 2, "position": {"x": 700, "y": 500}},
                  {"id": 3, "position": {"x": 400, "y": 100}}
                ],
                "gates": [{"node": 1, "t": 0.5}]
              }
            }
            """
        let file = TrackDesignFile.decode(Data(json.utf8))
        let design = try XCTUnwrap(file).design
        XCTAssertEqual(design.revision, 1)
        XCTAssertEqual(design.theme, "grass")
        XCTAssertEqual(design.nodes[0].fillet, 0)
        XCTAssertEqual(design.nodes[0].edge, .ground)
        XCTAssertFalse(design.nodes[0].kerb)
        XCTAssertEqual(design.gates[0].span, .corridor(reach: 150))
        XCTAssertEqual(design.grid, TrackDesign.StartGrid())
        XCTAssertNil(design.pit)
        XCTAssertTrue(design.extraWalls.isEmpty)
    }

    func testFutureVersionIsRejected() throws {
        var json = String(
            data: try TrackDesignFile(design: rectDesign()).encoded(), encoding: .utf8)!
        json = json.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        XCTAssertNil(TrackDesignFile.decode(Data(json.utf8)))
        XCTAssertNil(TrackDesignFile.decode(Data("not json".utf8)))
    }

    // MARK: - Validation

    private func assertThrows(
        _ design: TrackDesign, _ expected: TrackDesignError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try design.compile(), file: file, line: line) { error in
            XCTAssertEqual(error as? TrackDesignError, expected, file: file, line: line)
        }
        XCTAssertEqual(
            design.validationIssues().first, expected, file: file, line: line)
    }

    func testStructuralValidation() {
        var design = rectDesign()
        design.nodes.removeLast(2)
        assertThrows(design, .tooFewNodes(count: 2))

        design = rectDesign()
        design.nodes[2].id = 1
        assertThrows(design, .duplicateNodeID(1))

        design = rectDesign()
        design.width = 0
        assertThrows(design, .nonPositiveWidth)

        design = rectDesign()
        design.nodes[1].position = design.nodes[0].position
        assertThrows(design, .degenerateEdge(node: 1))

        design = rectDesign(gates: [])
        assertThrows(design, .noGates)

        design = rectDesign(gates: [TrackDesign.GateAnchor(node: 99, t: 0.5)])
        assertThrows(design, .unknownGateNode(gateIndex: 0, node: 99))

        design = rectDesign(gates: [TrackDesign.GateAnchor(node: 1, t: 0.5, span: .deck)])
        assertThrows(design, .deckSpanOffDeck(gateIndex: 0))
    }

    func testGeometricValidation() {
        // A ~180° reversal on one node cannot be filleted.
        let hairpin = TrackDesign(
            id: "bad-hairpin", name: "Bad", size: Vec2(1600, 1000), width: 60,
            nodes: [
                .init(id: 1, position: Vec2(0, 0)),
                .init(id: 2, position: Vec2(600, 0), fillet: 40),
                .init(id: 3, position: Vec2(100, 0)),
            ],
            gates: [TrackDesign.GateAnchor(node: 1, t: 0.5)]
        )
        assertThrows(hairpin, .degenerateTurn(node: 2))

        // Fillets that don't fit their edge.
        let cramped = TrackDesign(
            id: "cramped", name: "Cramped", size: Vec2(1600, 1000), width: 60,
            nodes: [
                .init(id: 1, position: Vec2(100, 100), fillet: 80),
                .init(id: 2, position: Vec2(200, 100), fillet: 80),
                .init(id: 3, position: Vec2(200, 600), fillet: 80),
                .init(id: 4, position: Vec2(100, 600), fillet: 80),
            ],
            gates: [TrackDesign.GateAnchor(node: 2, t: 0.5)]
        )
        XCTAssertThrowsError(try cramped.compile()) { error in
            guard
                case .filletOverflow(let node, let needed, let available) =
                    error as? TrackDesignError
            else { return XCTFail("expected filletOverflow, got \(error)") }
            XCTAssertEqual(node, 1)
            XCTAssertEqual(needed, 160, accuracy: 1e-6)  // 2 × 80·tan(45°)
            XCTAssertEqual(available, 100)
        }

        // A gate anchored inside a trimmed corner.
        let design = rectDesign(gates: [TrackDesign.GateAnchor(node: 1, t: 0.02)])
        assertThrows(design, .gateInsideFillet(gateIndex: 0))
    }

    func testLayerValidation() {
        // Fillet at a deck boundary.
        var design = bridgeDesign()
        design.nodes[4].fillet = 30  // node 5, the rampUp → deck join
        assertThrows(design, .filletAtLayerTransition(node: 5))

        // rampUp that never reaches a deck.
        design = bridgeDesign()
        design.nodes[4].edge = .ground  // node 5's leaving edge: deck → ground
        assertThrows(design, .deckNotBracketed(node: 5))
    }

    func testPlacementValidation() {
        // A grid pushed so far back it leaves the ribbon (the pole is the
        // first slot checked and already off).
        let farBack = rectDesign(grid: TrackDesign.StartGrid(back: 600))
        assertThrows(farBack, .startSlotOffRibbon(slot: 0))

        // A pit on the racing line.
        let badPit = rectDesign(pit: Vec2(800, 800))
        assertThrows(badPit, .pitOnRibbon)
    }

    // MARK: - Layer derivation

    func testBridgeCompilesLayersRampsAndWalls() throws {
        let track = try bridgeDesign().compile()
        // One straight deck edge with sharp ends = exactly one segment.
        XCTAssertEqual(track.elevatedSegments.count, 1)
        XCTAssertEqual(track.rampSegments.count, 2)
        XCTAssertEqual(track.ramps.count, 2)

        let up = track.ramps[0]
        XCTAssertEqual(up.fromLayer, 0)
        XCTAssertEqual(up.toLayer, 1)
        // The transition line sits at the deck-start node, slightly
        // narrower than the ribbon, facing along the deck.
        XCTAssertEqual((up.a + (up.b - up.a) * 0.5).distance(to: Vec2(900, 200)), 0, accuracy: 1e-9)
        XCTAssertEqual(up.a.distance(to: up.b), 2 * (track.width / 2 - 2), accuracy: 1e-9)
        XCTAssertGreaterThan(up.forward.dot(Vec2(-1, 0)), 0.99)

        let down = track.ramps[1]
        XCTAssertEqual(down.fromLayer, 1)
        XCTAssertEqual(down.toLayer, 0)
        XCTAssertEqual(
            (down.a + (down.b - down.a) * 0.5).distance(to: Vec2(700, 200)), 0, accuracy: 1e-9)

        // 4 boundary walls + 2 retaining walls per ramp edge.
        XCTAssertEqual(track.walls.count, 8)

        // The deck gate compiled onto layer 1.
        XCTAssertEqual(track.gates[0].layer, 1)
        XCTAssertEqual(track.gates[1].layer, 0)
    }

    // MARK: - Gates and grid

    func testCorridorGateSpansInfieldToWall() throws {
        let track = try rectDesign().compile()
        // Gate 0: right side (edge from node 2 up), anchored mid-edge.
        let gate = track.gates[0]
        XCTAssertEqual(gate.a.x, 1100, accuracy: 1e-9)  // 1300 − (50 + 150)
        XCTAssertEqual(gate.a.y, 500, accuracy: 1e-9)
        XCTAssertEqual(gate.b.x, 1592, accuracy: 1e-9)  // boundary inset 8
        XCTAssertEqual(gate.b.y, 500, accuracy: 1e-9)
        XCTAssertGreaterThan(gate.forward.dot(Vec2(0, -1)), 0.99)
    }

    func testStartGridDerivesFromLastGate() throws {
        let track = try rectDesign().compile()
        // Start gate at (800, 800) driving +x; infield is up-screen (−y).
        XCTAssertEqual(track.startHeading, 0, accuracy: 1e-9)
        XCTAssertEqual(track.startSlots.count, 4)
        for (i, slot) in track.startSlots.enumerated() {
            XCTAssertEqual(slot.x, 800 - 70 - Double(i) * 50, accuracy: 1e-9)
            XCTAssertEqual(slot.y, i % 2 == 0 ? 772 : 828, accuracy: 1e-9)
        }
        // Pole crosses the start gate driving forward.
        let pole = track.startSlots[0]
        XCTAssertTrue(
            track.gates[track.gates.count - 1]
                .crossedForward(movingFrom: pole, to: pole + Vec2(400, 0)))
    }
}
