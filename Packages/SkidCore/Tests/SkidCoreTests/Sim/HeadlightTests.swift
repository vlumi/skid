import XCTest

@testable import SkidCore

/// **The headlight cone, and the clipping that killed its predecessor.**
///
/// The old cone was a fixed shape clipped after the fact: it vanished under ramp edges
/// and shone through walls. Each reported failure mode is a test here, phrased as
/// "this ray must / must not pass this wall" — and the cone's construction (rays
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

    /// Full reach, measured from the apex at the car's center.
    private var range: Double { Headlight.apexDepth + Headlight.reach }

    // MARK: - The shape itself

    /// **The spec, pinned**: the apex inside the car, the cone leaving it at the
    /// car's full width, reaching under a car length past the nose — one plain cone,
    /// wide enough to read at race zoom.
    func testTheConeIsAFacingCueNotABeam() {
        XCTAssertLessThanOrEqual(Headlight.apexDepth, CarGeometry.length / 2)
        XCTAssertGreaterThanOrEqual(Headlight.noseHalfWidth * 2, CarGeometry.width)
        XCTAssertLessThan(Headlight.reach, CarGeometry.length)
        let tipSpread = 2 * sin(Headlight.halfAngle) * range
        XCTAssertLessThan(tipSpread, CarGeometry.width * 3)
    }

    /// Unobstructed, every ray starts on the nose line and reaches full length, and
    /// the cone is symmetric about the heading.
    func testAnOpenConeIsFullAndSymmetric() {
        let rays = Headlight.rays(car: car(), track: openTrack())
        XCTAssertEqual(rays.count, Headlight.rayCount)
        for ray in rays {
            // The lit part starts where the cone leaves the car: the nose line.
            XCTAssertEqual(ray.near.x, Headlight.apexDepth, accuracy: 1e-9)
            XCTAssertEqual(Vec2.zero.distance(to: ray.tip), range, accuracy: 1e-9)
        }
        for (left, right) in zip(rays, rays.reversed()) {
            XCTAssertEqual(left.tip.y, -right.tip.y, accuracy: 1e-9, "the cone is lopsided")
        }
    }

    // MARK: - Walls (the shine-through bug)

    /// **Light does not pass a wall the car cannot pass.** A rail across the beam at
    /// the car's own level cuts the rays that meet it.
    func testARailAtOwnLevelBlocksTheLight() {
        let rail = Wall(from: Vec2(30, -60), to: Vec2(30, 60), height: 0, kind: .rail)
        let rays = Headlight.rays(car: car(), track: openTrack(walls: [rail]))
        // The nose sits 17 ahead of the center, so the wall is 13 past the nose.
        for ray in rays {
            XCTAssertLessThanOrEqual(ray.tip.x, 30 + 1e-9, "light shone through the rail")
        }
    }

    /// **A nose shoved into a wall does not light the far side.** Collision stops the
    /// car's CENTER, not its body — pressed against a wall, the nose can sit past the
    /// wall line. The apex at the center is what makes this hold: rays start on the
    /// legal side, so the wall cuts them before the nose line and the cone collapses
    /// instead of starting beyond the wall. Reported from device.
    func testANoseInsideTheWallStaysDark() {
        let rail = Wall(from: Vec2(10, -60), to: Vec2(10, 60), height: 0, kind: .rail)
        // Center legal at x=0; the nose line at x=17 is past the wall.
        let rays = Headlight.rays(car: car(), track: openTrack(walls: [rail]))
        for ray in rays {
            XCTAssertLessThanOrEqual(ray.tip.x, 10 + 1e-9, "a buried nose lit past its wall")
            XCTAssertEqual(
                ray.near.distance(to: ray.tip), 0, accuracy: 1e-9,
                "a ray stopped inside the car still had a lit span")
        }
    }

    /// **A deck rail does not block the ground car's light** — the light passes under
    /// the bridge exactly as the car does. This is the height gate doing for light
    /// what it already does for collision.
    func testADeckRailPassesTheGroundCarsLight() {
        let deckRail = Wall(from: Vec2(30, -60), to: Vec2(30, 60), height: 1, kind: .rail)
        let rays = Headlight.rays(car: car(), track: openTrack(walls: [deckRail]))
        for ray in rays {
            XCTAssertEqual(
                Vec2.zero.distance(to: ray.tip), range, accuracy: 1e-9,
                "a deck rail dimmed the road under the bridge")
        }
    }

    /// **A ramp's flank blocks light from outside, and not from its own road** — the
    /// embankment's one-way rule, inherited.
    func testAnEmbankmentBlocksOnlyFromOutside() {
        // Earth along y=30, its road on the +y side (outward points -y, at the car).
        let flank = Wall(
            from: Vec2(-60, 30), to: Vec2(80, 30), height: 0.5, kind: .embankment,
            outward: Vec2(0, -1))
        let track = openTrack(walls: [flank])
        // From outside (below, facing up into the flank): blocked.
        let outside = Headlight.rays(car: car(heading: .pi / 2), track: track)
        for ray in outside {
            XCTAssertLessThanOrEqual(ray.tip.y, 30 + 1e-9, "light shone through the earth")
        }
        // From the road it carries (above, at its height, facing down): passes — the
        // one-way rule that lets you drive off a ramp lets your light off it too.
        var onRamp = car(heading: -.pi / 2)
        onRamp.position = Vec2(0, 60)
        onRamp.height = 0.5
        let inside = Headlight.rays(car: onRamp, track: track)
        let full = inside.filter {
            abs(onRamp.position.distance(to: $0.tip) - range) < 1e-6
        }
        XCTAssertEqual(full.count, Headlight.rayCount, "the ramp blinded its own driver")
    }

    /// **Invisible barriers cast no shadows.** The map boundary and the level seals
    /// are enforced but never drawn; light dying at a line drawn as nothing reads as
    /// a bug.
    func testInvisibleWallsDoNotBlockLight() {
        let walls = [
            Wall(from: Vec2(25, -60), to: Vec2(25, 60), height: 0, kind: .boundary),
            Wall(from: Vec2(30, -60), to: Vec2(30, 60), height: 1, kind: .gate),
        ]
        let rays = Headlight.rays(car: car(), track: openTrack(walls: walls))
        for ray in rays {
            XCTAssertEqual(Vec2.zero.distance(to: ray.tip), range, accuracy: 1e-9)
        }
    }

    // MARK: - Decks (the lost-under-the-ramp bug)

    /// **A road climbing ahead does not cut the beam** — the reported edge case. The
    /// rising stretch is under a level of clearance, so the light runs up it.
    func testARampAheadDoesNotClipTheBeam() {
        let track = Track(
            centerline: [Vec2(20, 0), Vec2(200, 0)],
            width: 120, heights: [0.4, 0.4], size: Vec2(2_000, 2_000))
        let rays = Headlight.rays(car: car(), track: track)
        for ray in rays {
            XCTAssertEqual(
                Vec2.zero.distance(to: ray.tip), range, accuracy: 1e-9,
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
        XCTAssertTrue(
            (Headlight.apexDepth + 2..<range).contains(footprintEdge),
            "the fixture must put the deck edge inside the beam; it is at \(footprintEdge)")
        let rays = Headlight.rays(car: car(), track: track)
        for ray in rays {
            XCTAssertLessThanOrEqual(
                ray.tip.x, footprintEdge + 1e-9,
                "the beam reached under (and would paint over) the deck")
        }
        // And a deck car's own light up there is NOT cut by its own road.
        let deckCar = CarState(position: Vec2(120, 0), heading: .pi / 2, height: 1)
        for ray in Headlight.rays(car: deckCar, track: track) {
            XCTAssertEqual(deckCar.position.distance(to: ray.tip), range, accuracy: 1e-9)
        }
    }

    // MARK: - Cost

    /// The cone at a busy spot on the worst real track, timed — the number the design
    /// promised to measure rather than assume. Clover carries 866 walls.
    func testTheConeIsCheapOnTheWorstTrack() {
        let track = TrackLibrary.track(id: "clover")
        let slot = track.startSlots.first ?? .zero
        let state = CarState(position: slot, heading: 1.2)
        let start = Date()
        var count = 0
        for _ in 0..<1_000 {
            count += Headlight.rays(car: state, track: track).count
        }
        let perCar = Date().timeIntervalSince(start) / 1_000
        print("PROBE cone cost on clover: \(Int(perCar * 1_000_000)) µs (\(count / 1_000) rays)")
        XCTAssertLessThan(perCar, 0.002, "a cone costs \(perCar * 1000) ms — too slow for 4/frame")
    }
}
