import XCTest

@testable import SkidCore

/// **The headlight fan, and the clipping that killed its predecessor.**
///
/// The old cone was a fixed shape clipped after the fact: it vanished under ramp edges
/// and shone through walls. Each reported failure mode is a test here, phrased as
/// "this ray must / must not pass this wall" — and the fan's construction (rays
/// shortened, never polygons subtracted) is what makes them hold.
final class HeadlightTests: XCTestCase {
    /// A car at the origin facing +x, on open ground with the given walls.
    private func openTrack(walls: [Wall] = []) -> Track {
        Track(
            centerline: [Vec2(-10_000, 5_000), Vec2(10_000, 5_000)],
            width: 120, walls: walls, size: Vec2(20_000, 10_000))
    }

    private func car(height: Double = 0, heading: Double = 0) -> CarState {
        CarState(position: .zero, heading: heading, height: height)
    }

    // MARK: - The shape itself

    /// **Shorter than the car, a bit wider than it** — the spec, pinned.
    func testTheFanIsAFacingCueNotABeam() {
        XCTAssertLessThan(Headlight.reach, CarGeometry.length)
        XCTAssertGreaterThan(Headlight.tipHalfWidth * 2, CarGeometry.width)
        XCTAssertLessThan(Headlight.tipHalfWidth * 2, CarGeometry.width * 1.6)
    }

    /// Unobstructed, every ray reaches full length and the fan is symmetric about
    /// the heading.
    func testAnOpenFanIsFullAndSymmetric() {
        let fan = Headlight.fan(car: car(), track: openTrack())
        XCTAssertEqual(fan.count, Headlight.rayCount + 1)
        let nose = fan[0]
        for tip in fan.dropFirst() {
            XCTAssertEqual(nose.distance(to: tip), Headlight.reach, accuracy: 1e-9)
        }
        for (near, far) in zip(fan.dropFirst(), fan.dropFirst().reversed()) {
            XCTAssertEqual(near.y, -far.y, accuracy: 1e-9, "the fan is lopsided")
        }
    }

    // MARK: - Walls (the shine-through bug)

    /// **Light does not pass a wall the car cannot pass.** A rail across the beam at
    /// the car's own level cuts the rays that meet it.
    func testARailAtOwnLevelBlocksTheLight() {
        let rail = Wall(from: Vec2(30, -40), to: Vec2(30, 40), height: 0, kind: .rail)
        let fan = Headlight.fan(car: car(), track: openTrack(walls: [rail]))
        // The nose sits 17 ahead of the center, so the wall is 13 past the nose.
        for tip in fan.dropFirst() {
            XCTAssertLessThanOrEqual(tip.x, 30 + 1e-9, "light shone through the rail")
        }
    }

    /// **A deck rail does not block the ground car's light** — the light passes under
    /// the bridge exactly as the car does. This is the height gate doing for light
    /// what it already does for collision.
    func testADeckRailPassesTheGroundCarsLight() {
        let deckRail = Wall(from: Vec2(30, -40), to: Vec2(30, 40), height: 1, kind: .rail)
        let fan = Headlight.fan(car: car(), track: openTrack(walls: [deckRail]))
        for tip in fan.dropFirst() {
            XCTAssertEqual(
                Vec2(17, 0).distance(to: tip), Headlight.reach, accuracy: 1e-9,
                "a deck rail dimmed the road under the bridge")
        }
    }

    /// **A ramp's flank blocks light from outside, and not from its own road** — the
    /// embankment's one-way rule, inherited.
    func testAnEmbankmentBlocksOnlyFromOutside() {
        // Earth along y=30, its road on the +y side (outward points -y, at the car).
        let flank = Wall(
            from: Vec2(-40, 30), to: Vec2(80, 30), height: 0.5, kind: .embankment,
            outward: Vec2(0, -1))
        let track = openTrack(walls: [flank])
        // From outside (below, facing up into the flank): blocked.
        let outside = Headlight.fan(car: car(heading: .pi / 2), track: track)
        for tip in outside.dropFirst() {
            XCTAssertLessThanOrEqual(tip.y, 30 + 1e-9, "light shone through the earth")
        }
        // From the road it carries (above, at its height, facing down): passes — the
        // one-way rule that lets you drive off a ramp lets your light off it too.
        var onRamp = car(heading: -.pi / 2)
        onRamp.position = Vec2(0, 60)
        onRamp.height = 0.5
        let inside = Headlight.fan(car: onRamp, track: track)
        let full = inside.dropFirst().filter {
            abs(Vec2(0, 43).distance(to: $0) - Headlight.reach) < 1e-6
        }
        XCTAssertEqual(full.count, Headlight.rayCount, "the ramp blinded its own driver")
    }

    /// **Invisible barriers cast no shadows.** The map boundary and the level seals
    /// are enforced but never drawn; light dying at a line drawn as nothing reads as
    /// a bug.
    func testInvisibleWallsDoNotBlockLight() {
        let walls = [
            Wall(from: Vec2(25, -40), to: Vec2(25, 40), height: 0, kind: .boundary),
            Wall(from: Vec2(30, -40), to: Vec2(30, 40), height: 1, kind: .gate),
        ]
        let fan = Headlight.fan(car: car(), track: openTrack(walls: walls))
        for tip in fan.dropFirst() {
            XCTAssertEqual(Vec2(17, 0).distance(to: tip), Headlight.reach, accuracy: 1e-9)
        }
    }

    // MARK: - Decks (the lost-under-the-ramp bug)

    /// **A road climbing ahead does not cut the beam** — the reported edge case. The
    /// rising stretch is under a level of clearance, so the light runs up it.
    func testARampAheadDoesNotClipTheBeam() {
        let track = Track(
            centerline: [Vec2(20, 0), Vec2(200, 0)],
            width: 120, heights: [0.4, 0.4], size: Vec2(2_000, 2_000))
        let fan = Headlight.fan(car: car(), track: track)
        for tip in fan.dropFirst() {
            XCTAssertEqual(
                Vec2(17, 0).distance(to: tip), Headlight.reach, accuracy: 1e-9,
                "the beam was clipped by road the car can drive onto")
        }
    }

    /// **A deck a full level up covers the beam** — the bridge's shadow. Rays stop at
    /// its edge instead of painting onto the deck the overlay pass draws above.
    func testACoveringDeckCutsTheBeamAtItsEdge() {
        // The deck's FOOTPRINT is what covers, and it is wide: ~81 units either side
        // of the centerline at deck height. Placed so its edge falls mid-beam.
        let track = Track(
            centerline: [Vec2(120, -400), Vec2(120, 400)],
            width: 120, heights: [1, 1], size: Vec2(2_000, 2_000))
        let footprintEdge = 120 - track.footprintHalfWidth(atHeight: 1)
        let nose = 17.0
        XCTAssertTrue(
            (nose + 2..<nose + Headlight.reach).contains(footprintEdge),
            "the fixture must put the deck edge inside the beam; it is at \(footprintEdge)")
        let fan = Headlight.fan(car: car(), track: track)
        for tip in fan.dropFirst() {
            XCTAssertLessThanOrEqual(
                tip.x, footprintEdge + 1e-9,
                "the beam reached under (and would paint over) the deck")
        }
        // And a deck car's own light up there is NOT cut by its own road.
        let onDeck = Headlight.fan(
            car: CarState(position: Vec2(120, 0), heading: .pi / 2, height: 1),
            track: track)
        for tip in onDeck.dropFirst() {
            XCTAssertEqual(
                Vec2(120, 17).distance(to: tip), Headlight.reach, accuracy: 1e-9)
        }
    }

    // MARK: - Cost

    /// The fan at a busy spot on the worst real track, timed — the number the design
    /// promised to measure rather than assume. Clover carries 866 walls.
    func testTheFanIsCheapOnTheWorstTrack() {
        let track = TrackLibrary.track(id: "clover")
        let slot = track.startSlots.first ?? .zero
        let state = CarState(position: slot, heading: 1.2)
        let start = Date()
        var points = 0
        for _ in 0..<1_000 {
            points += Headlight.fan(car: state, track: track).count
        }
        let perFan = Date().timeIntervalSince(start) / 1_000
        print("PROBE fan cost on clover: \(Int(perFan * 1_000_000)) µs (\(points / 1_000) points)")
        XCTAssertLessThan(perFan, 0.002, "a fan costs \(perFan * 1000) ms — too slow for 4/frame")
    }
}
