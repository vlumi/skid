import XCTest

@testable import SkidCore

/// The overlap check must measure ASPHALT, not centerlines. Found on device and
/// confirmed by an independent investigation: a rising curve was refused where
/// the drawn ribbons had 41.8 units of clear grass between them, because the
/// checker compared centerline distance (113.87) against a flat threshold (114)
/// calibrated for PARALLEL roads — where centerlines under a road width apart
/// really do share asphalt. End-on or oblique, they don't.
final class RibbonGapTests: XCTestCase {
    private typealias Catalog = PieceCatalog.ID

    /// The reported track: loose end at height 0.5, mid-climb.
    private func base() throws -> TrackLayout {
        try TrackCode.decode("AXcBBx8KDBEFeQUCAQADBQAAAAAA")
    }

    /// **The reported case, all three pitches.** The 2D geometry is identical
    /// for up, flat and down — same exit point, same 113.87 centerline gap,
    /// same 41.8 units of real clearance — so all three must be judged alike,
    /// and all three must be LEGAL. (Before the fix: all three refused on main;
    /// the first crossing rule then allowed only down, because the loose end's
    /// sampled height happened to land within tolerance of the other road — a
    /// height lottery over identical geometry.)
    func testTheRisingCurveWithRealClearanceIsAllowed() throws {
        let base = try base()
        for pitch in [Pitch.up, .flat, .down] {
            XCTAssertTrue(
                TrackValidator.canAppend(
                    run: [PlannedPiece(id: Catalog.curve45MediumLeft, pitch: pitch)],
                    to: base),
                "pitch \(pitch): 41.8 units of real clearance must not be an overlap")
        }
    }

    /// The user's reference layouts — previously refused as overlaps despite
    /// visible grass between the sweeps — validate.
    func testTheReferenceLayoutsValidate() throws {
        for code in [
            "AYUBBh8KDBELBQIBAAMFAAAAAAA",  // the same shape all at ground level
            "ATUBCR8KDBEFeQV6BQIBAAMFAAAAAAA",  // with a ramp down at the end
            "AQcBCR8KDBF5BQV4BQIBAAMFAAAAAAA",  // with the ramp one piece earlier
        ] {
            let layout = try TrackCode.decode(code)
            XCTAssertFalse(
                TrackValidator.validate(layout).problems.contains(.overlap),
                "\(code): no asphalt touches, so nothing overlaps")
        }
    }

    /// **Parallel roads keep the old calibration exactly.** Side by side, the
    /// penetration test reduces to the old threshold: centerlines a full road
    /// width apart (the shared-kerb fit) are legal, centerlines under 114 are
    /// an overlap. This is the case the old metric was right about.
    func testParallelRibbonsKeepTheOldCalibration() {
        let width = Double(PieceCatalog.width)
        // Two long parallel horizontal segments, offset vertically by d.
        func penetration(_ d: Double) -> Double {
            RoadProximity.ribbonPenetration(
                Vec2(0, 0), Vec2(240, 0), Vec2(0, d), Vec2(240, d))
        }
        XCTAssertEqual(
            penetration(width), 0, accuracy: 1e-9,
            "the shared-kerb fit touches exactly and must not penetrate")
        XCTAssertGreaterThan(
            penetration(113), width - 113 - 1e-9,
            "under the old threshold, parallel ribbons genuinely interpenetrate")
        XCTAssertLessThanOrEqual(
            penetration(115), width - 115 + 1e-9,
            "slack: five units of parallel penetration stays legal, as before")
    }

    /// End-on, the old metric overstated wildly: a segment ENDING 113.87 from
    /// another road's centerline has its asphalt tens of units clear, because
    /// asphalt extends sideways from a road, not off its end.
    func testAnEndOnApproachDoesNotPenetrate() {
        // Vertical segment ending 113.87 above a horizontal one, oblique-ish.
        let penetration = RoadProximity.ribbonPenetration(
            Vec2(0, 0), Vec2(240, 0),
            Vec2(160, -113.87 - 120), Vec2(120, -113.87))
        XCTAssertEqual(penetration, 0, accuracy: 1e-9, "no shared asphalt end-on")
    }
}
