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

    /// And the harder the hit, the more it costs — a light brush is not the same as
    /// a heavy scrape.
    func testAHarderGrazeCostsMore() {
        var raceSoft = race()
        var raceHard = race()
        let soft = graze(degrees: 4, speed: 400, into: &raceSoft)
        let hard = graze(degrees: 25, speed: 400, into: &raceHard)
        let softLoss = abs(soft.before.velocity.x) - abs(soft.after.velocity.x)
        let hardLoss = abs(hard.before.velocity.x) - abs(hard.after.velocity.x)
        XCTAssertGreaterThan(hardLoss, softLoss, "a steeper graze should cost more speed")
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
        // The band the maintainer asked for: 30° is still a GLANCE in an arcade
        // game, near-90° is a head-on. So no bounce at all up to 30, full by 75.
        XCTAssertEqual(rebound(6), 0, accuracy: 0.001, "a 6° graze must not bounce")
        XCTAssertEqual(rebound(30), 0, accuracy: 0.001, "30° is still a glance")
        XCTAssertLessThan(rebound(45), rebound(60), "the band should rise through it")
        XCTAssertLessThan(rebound(60), rebound(80), "and keep rising toward head-on")
        XCTAssertGreaterThan(rebound(88), 0.3, "a square hit should properly bounce")
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

        // Half a second of HELD contact: each tick the car is put back just inside
        // the wall, still angled into it — a driver leaning on the barrier. Without
        // re-establishing both the position and the into-wall velocity, the first
        // bounce lifts it clear and every later tick is a no-op (which is what the
        // first version of this loop measured: one tick's worth, thirty times).
        for _ in 0..<30 {
            let speed = car.velocity.length
            guard speed > 1 else { break }
            car.velocity = Vec2(cos(radians), -sin(radians)) * speed
            let from = Vec2(car.position.x, CarGeometry.radius + 1)
            car.position = Vec2(car.position.x + car.velocity.x * Race.dt, CarGeometry.radius - 1)
            _ = race.collideWithWalls(car: &car, movedFrom: from, walls: [wall])
        }
        XCTAssertLessThan(
            car.velocity.length, start * 0.5,
            "half a second of scraping should cost most of the speed")
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
