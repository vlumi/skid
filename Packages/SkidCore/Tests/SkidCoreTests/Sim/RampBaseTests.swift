import XCTest

@testable import SkidCore

/// **A ramp blocks from its own base, not from the ground.** A 1→2 ramp stands
/// on the deck, so its flanks must stop cars at 1 while a ground car passes
/// underneath freely.
///
/// The plan expected this to need fixing — the wall emission looked like it
/// assumed every ramp rises from 0. It does not: each rail takes its own
/// sample's height, and `Race.blocks` derives the floor as `trunc(height)`. So
/// the behavior is already right, and these tests exist to keep it that way
/// once ramps above the ground actually become buildable.
final class RampBaseTests: XCTestCase {
    private func race() -> Race {
        Race(
            track: Track(
                centerline: [Vec2(-500, 0), Vec2(500, 0)], width: 200,
                startSlots: [.zero], size: Vec2(1000, 1000)),
            players: [PlayerID(0)])
    }

    private func car(atHeight height: Double) -> CarState {
        var car = CarState(position: .zero)
        car.height = height
        return car
    }

    /// A rail partway up a 1→2 ramp guards the storey it stands on.
    func testAnUpperStoreyRampBlocksFromItsOwnBase() {
        let rail = Wall(from: Vec2(0, 0), to: Vec2(100, 0), height: 1.4, kind: .rail)
        let race = race()

        XCTAssertTrue(race.blocks(rail, car: car(atHeight: 1.0)), "the deck it stands on")
        XCTAssertTrue(race.blocks(rail, car: car(atHeight: 1.4)), "and up to its own height")
        XCTAssertFalse(
            race.blocks(rail, car: car(atHeight: 0)),
            "a GROUND car must pass underneath — the deck is already the roof")
        XCTAssertFalse(race.blocks(rail, car: car(atHeight: 0.5)), "still below the base")
        XCTAssertFalse(race.blocks(rail, car: car(atHeight: 1.6)), "and over the top is over")
    }

    /// The ground-level case, unchanged: a 0→1 ramp fences from the ground.
    func testAGroundRampStillBlocksFromTheGround() {
        let rail = Wall(from: Vec2(0, 0), to: Vec2(100, 0), height: 0.4, kind: .rail)
        let race = race()

        XCTAssertTrue(race.blocks(rail, car: car(atHeight: 0)))
        XCTAssertTrue(race.blocks(rail, car: car(atHeight: 0.4)))
        XCTAssertFalse(race.blocks(rail, car: car(atHeight: 1.0)), "a deck car clears it")
    }

    /// The mouth gate is a HEIGHT test, not a direction test — "be of the upper
    /// level to pass" — and reads the mouth's own height, so it generalizes to
    /// an upper storey without change.
    func testTheMouthGateScalesWithTheStorey() {
        let race = race()
        let deckMouth = Wall(from: Vec2(0, 0), to: Vec2(100, 0), height: 1, kind: .gate)
        XCTAssertTrue(race.blocks(deckMouth, car: car(atHeight: 0.5)), "below: refused")
        XCTAssertFalse(race.blocks(deckMouth, car: car(atHeight: 1)), "of the level: passes")

        let upperMouth = Wall(from: Vec2(0, 0), to: Vec2(100, 0), height: 2, kind: .gate)
        XCTAssertTrue(race.blocks(upperMouth, car: car(atHeight: 1.5)), "one storey below")
        XCTAssertFalse(race.blocks(upperMouth, car: car(atHeight: 2)), "of the level: passes")
        XCTAssertFalse(
            race.blocks(upperMouth, car: car(atHeight: 0)),
            "a gate hangs one storey, so the ground passes under an upper mouth")
    }
}
