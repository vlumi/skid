import XCTest

@testable import SkidCore

/// **A road style is a property of the whole track, not a mark on a piece.**
///
/// It exists because lane markings are not decals: they cover every piece, they must
/// appear on pieces added later without being placed again, and a piece inserted
/// mid-track must not leave a gap. These pin the storage half of that.
final class RoadStyleTests: XCTestCase {
    private var layout: TrackLayout {
        TrackLayout(pieces: [PieceCatalog.startPieceID, 1, 1, 1])
    }

    /// **Circuit is the default**, so every existing track is unchanged.
    func testCircuitIsTheDefault() {
        XCTAssertEqual(layout.roadStyle, .circuit)
    }

    /// **A circuit's code is byte-identical to before the style existed.** The section is
    /// omitted at the default, which is what stops this change rewriting every code — and
    /// therefore every content-hashed library id.
    func testACircuitCodeCarriesNoStyleSection() throws {
        var road = layout
        road.roadStyle = .road
        let circuitCode = TrackCode.encode(layout)
        let roadCode = TrackCode.encode(road)
        XCTAssertNotEqual(circuitCode, roadCode, "the style must reach the code")
        XCTAssertLessThan(
            circuitCode.count, roadCode.count,
            "a circuit should be the SHORTER code — its style section is omitted")
    }

    /// It survives the wire.
    func testTheStyleRoundTrips() throws {
        for style in TrackLayout.RoadStyle.allCases {
            var original = layout
            original.roadStyle = style
            let back = try XCTUnwrap(try? TrackCode.decode(TrackCode.encode(original)))
            XCTAssertEqual(back.roadStyle, style)
        }
    }

    /// **An unknown style decodes as a circuit rather than failing.** A code from a
    /// later build should still be raceable, just plainer — refusing it would make a
    /// shared track unopenable over a purely cosmetic difference.
    func testAnUnknownStyleFallsBackToCircuit() {
        XCTAssertNil(
            TrackLayout.RoadStyle(rawValue: 99),
            "99 must be an unknown style for this test to mean anything")
        // What `decode` does with that nil, spelled out: the fallback, not a throw.
        let style = TrackLayout.RoadStyle(rawValue: 99) ?? .circuit
        XCTAssertEqual(style, .circuit)
    }
}
