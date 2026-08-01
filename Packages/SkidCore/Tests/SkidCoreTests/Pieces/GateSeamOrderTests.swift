import XCTest

@testable import SkidCore

/// **One track, one code** — the property the share code's identity rests on
/// (dedup, per-track hiscores, and later a signature over the bytes).
///
/// It did not hold. `gateSeams` was only sorted by `rotate(to:)`, which
/// early-returns on `guard index != 0` — and in the canonical spelling the
/// start piece IS at index 0, so the ordinary encode path never sorted. Two
/// spellings of the same gate set produced two different codes with two
/// different CRCs, and the shipped `eight` built-in carried its gates unsorted.
final class GateSeamOrderTests: XCTestCase {
    private func ring() throws -> TrackLayout {
        try TrackCode.decode(TestTracks.Code.bridgeRing)
    }

    /// The regression: the same gates in a different order are the same track.
    func testGateOrderDoesNotChangeTheCode() throws {
        let base = try ring()
        XCTAssertGreaterThanOrEqual(
            base.gateSeams.count, 3, "needs 3+ gates or a reordering proves nothing")

        var scrambled = base
        scrambled.gateSeams = base.gateSeams.reversed()
        var rotated = base
        rotated.gateSeams = Array(base.gateSeams.dropFirst() + base.gateSeams.prefix(1))

        XCTAssertEqual(TrackCode.encode(scrambled), TrackCode.encode(base))
        XCTAssertEqual(TrackCode.encode(rotated), TrackCode.encode(base))
    }

    /// `init` sorts. Its own case, because **`didSet` does not fire for an
    /// assignment inside `init`** — dropping the sort there left every other
    /// test green, so the two halves of this fix need separate cover.
    func testInitSortsSeams() {
        let layout = TrackLayout(
            pieces: [PieceCatalog.startPieceID, PieceCatalog.ID.shortStraight],
            gateSeams: [1, 0])
        XCTAssertEqual(layout.gateSeams, [0, 1])
    }

    /// The invariant itself, on every path that can build a layout — including
    /// `rotate(to: 0)`, the early-return case that let this through.
    func testEveryConstructionPathLeavesSeamsAscending() throws {
        var fromInit = try ring()
        fromInit.gateSeams = [8, 0, 12, 4]
        XCTAssertEqual(fromInit.gateSeams, [0, 4, 8, 12])

        // A hand-built body whose gates section is out of order on the wire.
        let decoded = try TrackCode.decode(TestTracks.Code.bridgeRing)
        XCTAssertEqual(decoded.gateSeams, decoded.gateSeams.sorted())

        var mutated = try ring()
        mutated.insert(PieceCatalog.ID.shortStraight, at: 2)
        XCTAssertEqual(mutated.gateSeams, mutated.gateSeams.sorted())
        mutated.remove(at: 2)
        XCTAssertEqual(mutated.gateSeams, mutated.gateSeams.sorted())

        var rotatedToZero = try ring()
        rotatedToZero.gateSeams = [8, 0, 12, 4]
        rotatedToZero.rotate(to: 0)
        XCTAssertEqual(
            rotatedToZero.gateSeams, [0, 4, 8, 12],
            "rotate(to: 0) early-returns — the sort cannot live there")
    }

    /// The built-in that carried the bug. Its code changed with this fix, so
    /// this pins what it decodes to rather than trusting the new literal.
    func testTheEightsGatesAreAscending() throws {
        let eight = try XCTUnwrap(TrackLibrary.layout(id: "eight"))
        XCTAssertEqual(eight.gateSeams, [0, 4, 12])
    }
}
