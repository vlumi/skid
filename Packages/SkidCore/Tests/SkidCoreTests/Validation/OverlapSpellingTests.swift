import XCTest

@testable import SkidCore

/// **One track, one verdict.** A closed ring can be written starting from any of
/// its pieces, so overlap legality must not depend on which — otherwise the same
/// road is buildable one way round and refused the other.
///
/// It did depend on it. Reported from device: a piece that obviously fitted was
/// refused, and adding it from the other end worked. `coversJoinZone` was the
/// culprit — a rule for protecting the gap a closure still has to land in, applied
/// to rings that were already closed, where which pieces sit either side of the
/// seam is purely a matter of spelling.
final class OverlapSpellingTests: XCTestCase {
    /// The reported case: a 16-piece chain plus the medium-right curve, pitched
    /// down, that closes it. Refused as built, accepted when respelled.
    func testTheReportedTrackIsAcceptedHoweverItIsSpelled() throws {
        let broken = try TrackCode.decode("AQgBDXoEeAQfCgwRBXkFBRUCAgIOAwUcmBuoBgcCBAEFAQE")
        var closed = broken
        closed.append(contentsOf: PieceExpansion.expand(6, mode: .down))
        XCTAssertTrue(closed.walk().openEnds.isEmpty, "fixture must close the ring")

        XCTAssertFalse(
            TrackValidator.validate(closed).problems.contains(.overlap),
            "the closing piece fits — the road is the same road whichever end it came from")
    }

    /// The invariant, on the same track: every spelling agrees.
    func testEverySpellingOfTheReportedTrackAgrees() throws {
        let broken = try TrackCode.decode("AQgBDXoEeAQfCgwRBXkFBRUCAgIOAwUcmBuoBgcCBAEFAQE")
        var closed = broken
        closed.append(contentsOf: PieceExpansion.expand(6, mode: .down))
        try assertVerdictIsSpellingIndependent(closed, "reported track")
    }

    /// And on the built-ins, which cover bridges, ramps and self-crossings.
    func testEverySpellingOfTheBuiltInsAgrees() throws {
        for builtin in TrackLibrary.builtins {
            try assertVerdictIsSpellingIndependent(
                try TrackCode.decode(builtin.code), builtin.name)
        }
    }

    private func assertVerdictIsSpellingIndependent(
        _ layout: TrackLayout, _ name: String
    ) throws {
        let expected = TrackValidator.validate(layout).problems.contains(.overlap)
        for offset in 1..<layout.pieces.count {
            var spelled = layout
            spelled.rotate(to: offset)
            guard spelled.pieces != layout.pieces else { continue }  // not a ring
            XCTAssertEqual(
                TrackValidator.validate(spelled).problems.contains(.overlap), expected,
                "\(name) spelled from \(offset) disagrees about overlap")
        }
    }
}
