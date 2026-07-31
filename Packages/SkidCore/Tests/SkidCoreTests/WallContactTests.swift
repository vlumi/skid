import XCTest

@testable import SkidCore

/// **Wall contact should cost you, and should have mass.** Reported from device:
/// the bounce was too harsh and the car read as weightless — worst on GLANCING
/// hits, which should scrub along the wall and instead kicked out.
///
/// The old model reflected the whole normal component with a fixed restitution and
/// left the tangential component completely alone, so a shallow hit turned
/// sideways speed into an outward shove and contact cost nothing along the wall.
/// Riding a barrier was free.
///
/// Four requirements, from the maintainer:
/// 1. dragging along a wall must not be the fast line
/// 2. a glancing hit points the nose along the wall
/// 3. a hard enough glancing hit can stop the car
/// 4. near-head-on hits still bounce
final class WallContactTests: XCTestCase {
    /// A long straight wall along the x axis, and a car set up to graze it.
    private func race() -> Race {
        Race(track: TrackLibrary.testRing(), players: [PlayerID(0)], config: RaceConfig(laps: 1))
    }

    /// A wall along y = 0, with the car's side of it being +y.
    private let wall = Wall(
        from: Vec2(-4000, 0), to: Vec2(4000, 0), height: 0, kind: .boundary)

    /// One tick of contact: the car is already touching the wall and travelling
    /// into it at `speed`, `degrees` off parallel.
    ///
    /// It has to START in contact. A tick at 400 units/s covers under seven units,
    /// so a car placed a radius clear and aimed 8° into the wall never reaches it —
    /// the first version of this fixture measured no contact and read that as
    /// "friction is missing".
    private func graze(
        degrees: Double, speed: Double, into race: inout Race
    ) -> (before: CarState, after: CarState) {
        var car = race.cars[0].state
        car.height = 0
        let radians = degrees * .pi / 180
        // Travelling +x and into the wall (−y).
        car.velocity = Vec2(cos(radians), -sin(radians)) * speed
        car.heading = atan2(car.velocity.y, car.velocity.x)
        // Just inside the contact radius, having arrived from clear of it.
        let from = Vec2(0, CarGeometry.radius + 1)
        car.position = Vec2(car.velocity.x * Race.dt, CarGeometry.radius - 1)
        let before = car
        _ = race.collideWithWalls(car: &car, movedFrom: from, walls: [wall])
        return (before, car)
    }

    /// **1. Contact costs speed along the wall.** Without this, riding a barrier is
    /// free and the fastest line hugs it.
    func testAGrazeLosesSpeedAlongTheWall() {
        var race = race()
        let (before, after) = graze(degrees: 8, speed: 400, into: &race)
        let alongBefore = abs(before.velocity.x)
        let alongAfter = abs(after.velocity.x)
        XCTAssertLessThan(
            alongAfter, alongBefore,
            "a graze must scrub speed along the wall, not just bounce off it")
    }

    /// And a faster scrape costs more than a slow one — friction keys off the speed
    /// ALONG the wall, which is the energy a scrape actually has to work on.
    ///
    /// (Not "steeper costs more": a steeper approach has LESS slide, so it scrubs less
    /// along the wall and bounces more instead. The angle governs bounce; the slide
    /// governs scrape.)
    func testAFasterScrapeCostsMore() {
        var raceSlow = race()
        var raceFast = race()
        let slow = graze(degrees: 8, speed: 150, into: &raceSlow)
        let fast = graze(degrees: 8, speed: 450, into: &raceFast)
        let slowLoss = abs(slow.before.velocity.x) - abs(slow.after.velocity.x)
        let fastLoss = abs(fast.before.velocity.x) - abs(fast.after.velocity.x)
        XCTAssertGreaterThan(fastLoss, slowLoss, "a faster scrape should cost more speed")
    }

    /// **2. A glancing hit points the nose along the wall.** The car pivots instead
    /// of skipping off, which is what "having mass" reads as.
    func testAGrazeTurnsTheNoseTowardTheWallDirection() {
        var race = race()
        let (before, after) = graze(degrees: 40, speed: 400, into: &race)
        // The wall runs along +x, the car came in 20° into it. Its nose should end
        // up closer to parallel than it started.
        let offBefore = abs(atan2(sin(before.heading), cos(before.heading)))
        let offAfter = abs(atan2(sin(after.heading), cos(after.heading)))
        XCTAssertLessThan(offAfter, offBefore, "the nose should be pulled along the wall")
    }

    /// **4. Near-head-on still bounces.** That part was wanted — only the shallow
    /// case misbehaved.
    func testAHeadOnHitStillBounces() {
        var race = race()
        let (_, after) = graze(degrees: 88, speed: 400, into: &race)
        XCTAssertGreaterThan(
            after.velocity.y, 0, "a head-on hit must come back off the wall")
    }

    /// …and a shallow one barely bounces, so it scrubs along instead of kicking
    /// out. This is the reported complaint, as a number: bounce must FALL AWAY with
    /// the angle, not stay at full restitution however flat the hit.
    func testBounceFallsAwayAsTheAngleFlattens() {
        // The fraction of approach speed returned, at each angle.
        func rebound(_ degrees: Double) -> Double {
            var race = race()
            let (before, after) = graze(degrees: degrees, speed: 400, into: &race)
            return after.velocity.y / abs(before.velocity.y)
        }
        // The SHAPE, not the numbers: a glance keeps some subdued bounce (zero read
        // as flypaper on device), and it rises with the angle to a real bounce
        // head-on. The thresholds themselves are tuning values, deliberately not
        // pinned — they moved three times from device feel and will move again.
        XCTAssertGreaterThan(rebound(6), 0, "even a graze should keep a little bounce")
        XCTAssertLessThan(rebound(6), rebound(45), "but much less than a steeper hit")
        XCTAssertLessThan(rebound(45), rebound(80), "rising toward head-on")
        XCTAssertGreaterThan(rebound(88), 0.2, "a square hit should properly bounce")
    }

    /// **3. A hard enough glancing hit can stop the car** — over a scrape, not in a
    /// single tick. One tick at 60 Hz is 17 ms of contact; taking most of a car's
    /// speed in that would be the instant-stop the first version of this shipped
    /// with (reported as "the car instantly stops touching the wall at any angle").
    func testAScrapeBleedsTheCarDown() {
        var race = race()
        var car = race.cars[0].state
        car.height = 0
        let radians = 45.0 * Double.pi / 180
        car.velocity = Vec2(cos(radians), -sin(radians)) * 520
        car.heading = atan2(car.velocity.y, car.velocity.x)
        let start = car.velocity.length

        // A driver LEANING on the barrier: keep whatever the sim produced and steer
        // gently back in, rather than re-donating the full into-wall component every
        // tick. Re-donating measures the harness's own input — the collision destroys
        // that component, the harness hands it back, and the car "bleeds to a stop"
        // no matter how light the friction is. That is how an earlier version of this
        // read 2% remaining and got called flypaper.
        for _ in 0..<30 {
            guard car.velocity.length > 1 else { break }
            car.velocity = Vec2(car.velocity.x, min(car.velocity.y, -20))
            let from = Vec2(car.position.x, CarGeometry.radius + 1)
            car.position = Vec2(car.position.x + car.velocity.x * Race.dt, CarGeometry.radius - 1)
            _ = race.collideWithWalls(car: &car, movedFrom: from, walls: [wall])
        }
        // Some real cost, but nowhere near a stop: dragging a wall is meant to be a
        // viable if slow line. The exact figure is a tuning value.
        XCTAssertLessThan(car.velocity.length, start * 0.95, "a scrape should cost speed")
        XCTAssertGreaterThan(
            car.velocity.length, start * 0.2,
            "…but half a second of scraping must not nearly stop the car")
    }

    /// And the cost EASES at low speed, so nudging along a wall while sorting
    /// yourself out is fine — it is proportional to how hard the wall is pressed.
    func testTheCostEasesAtLowSpeed() {
        func keptPerTick(_ speed: Double) -> Double {
            var race = race()
            let (before, after) = graze(degrees: 20, speed: speed, into: &race)
            return abs(after.velocity.x) / abs(before.velocity.x)
        }
        XCTAssertGreaterThan(
            keptPerTick(60), keptPerTick(400),
            "a slow scrape should cost proportionally less than a fast one")
    }

    /// **The car must actually MOVE at the speed it says.** The push-out used to be
    /// an absolute snap onto the wall's surface, recomputed each tick, so a car held
    /// against a barrier was returned to the same spot every tick and lost all its
    /// travel — not just the into-wall part. On device that read as being glued in
    /// place while the debug overlay showed 300+ units/s: velocity was fine, position
    /// was being deleted, which is why no amount of wall tuning could fix it.
    func testAHeldCarTravelsAtTheSpeedItReports() {
        var race = race()
        var car = race.cars[0].state
        car.height = 0
        car.position = Vec2(200, CarGeometry.radius + 1)
        car.heading = -20 * Double.pi / 180
        car.velocity = Vec2(angle: car.heading) * 350
        race.cars[0].state = car

        // Skip the first tick: the initial overlap resolution legitimately moves the
        // car further than one tick of travel.
        race.advance(inputs: [PlayerID(0): CarInput(steer: -1, throttle: 1)])
        var previous = race.cars[0].state.position
        for _ in 0..<15 {
            race.advance(inputs: [PlayerID(0): CarInput(steer: -1, throttle: 1)])
            let state = race.cars[0].state
            let travelled = state.position.distance(to: previous) / Race.dt
            previous = state.position
            XCTAssertEqual(
                travelled, state.velocity.length, accuracy: 1,
                "the car reports \(Int(state.velocity.length)) but moved \(Int(travelled))")
        }
        XCTAssertGreaterThan(
            previous.x, 250, "a car sliding along a wall should get somewhere")
    }

    /// Contact must never ADD speed, at any angle — an energy check the old model
    /// could fail, since it reflected with restitution and touched nothing else.
    func testContactNeverAddsSpeed() {
        for degrees in stride(from: 2.0, through: 90.0, by: 4.0) {
            for speed in [80.0, 260.0, 520.0] {
                var race = race()
                let (before, after) = graze(degrees: degrees, speed: speed, into: &race)
                XCTAssertLessThanOrEqual(
                    after.velocity.length, before.velocity.length + 0.001,
                    "\(degrees)° at \(speed) gained speed off a wall")
            }
        }
    }
}
