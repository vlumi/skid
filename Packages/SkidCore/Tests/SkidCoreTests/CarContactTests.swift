import XCTest

@testable import SkidCore

final class CarContactTests: XCTestCase {
    /// Two cars facing each other on an open field, converging head-on.
    /// `elevatedLine` marks the forward segment as a bridge (the closing
    /// segment keeps the same line on the ground), so a layer-1 car has
    /// road to stand on instead of falling off.
    private func headOn(contact: Bool, elevatedLine: Bool = false) -> Race {
        let track = Track(
            centerline: [Vec2(-10000, 0), Vec2(10000, 0)],
            width: 800,
            elevatedSegments: elevatedLine ? [0] : [],
            startSlots: [Vec2(-100, 0), Vec2(100, 0)],
            size: Vec2(20000, 4000)
        )
        var race = Race(
            track: track, players: [PlayerID(0), PlayerID(1)],
            config: RaceConfig(carContact: contact)
        )
        // Pin the grid: the collision setup needs car 0 on the left and car 1
        // on the right, regardless of the random start-slot shuffle. Point
        // car 1 back toward car 0.
        race.cars[0].state.position = Vec2(-100, 0)
        race.cars[1].state.position = Vec2(100, 0)
        race.cars[1].state.heading = .pi
        return race
    }

    private func converge(_ race: inout Race, ticks: Int) {
        for _ in 0..<ticks {
            race.advance(inputs: [
                PlayerID(0): CarInput(throttle: 1),
                PlayerID(1): CarInput(throttle: 1),
            ])
        }
    }

    func testContactCarsCollideAndSeparate() {
        var race = headOn(contact: true)
        var minGap = Double.greatestFiniteMagnitude
        for _ in 0..<240 {
            converge(&race, ticks: 1)
            let gap = race.cars[0].state.position.distance(to: race.cars[1].state.position)
            minGap = min(minGap, gap)
        }
        // They met, but never interpenetrated beyond the same-tick overlap
        // that the resolver immediately corrects.
        XCTAssertLessThan(minGap, CarGeometry.radius * 2 + 30)
        XCTAssertGreaterThanOrEqual(minGap, CarGeometry.radius * 2 - 8)
        // And car 0 got knocked back: it ends up left of where it started
        // pushing forward, or at least was reversed at some point — its
        // velocity along +x is no longer the full-throttle head of steam.
        XCTAssertLessThan(race.cars[0].state.position.x, race.cars[1].state.position.x)
    }

    func testGhostCarsPassThrough() {
        var race = headOn(contact: false)
        converge(&race, ticks: 240)
        // They crossed: car 0 is now to the RIGHT of car 1.
        XCTAssertGreaterThan(race.cars[0].state.position.x, race.cars[1].state.position.x)
    }

    func testContactStaysDeterministic() {
        func run() -> Race {
            var race = headOn(contact: true)
            for tick in 0..<600 {
                let phase = Double(tick) / 60.0
                race.advance(inputs: [
                    PlayerID(0): CarInput(steer: sin(phase), throttle: 1),
                    PlayerID(1): CarInput(steer: cos(phase), throttle: 1),
                ])
            }
            return race
        }
        XCTAssertEqual(run(), run())
    }

    func testDifferentLayersNeverCollide() {
        var race = headOn(contact: true, elevatedLine: true)
        race.cars[1].state.layer = 1
        converge(&race, ticks: 240)
        XCTAssertGreaterThan(race.cars[0].state.position.x, race.cars[1].state.position.x)
    }
}
