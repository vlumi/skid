import Foundation
import Testing

@testable import SkidCore
@testable import SkidKit

/// **The field you asked for is the field you get.**
///
/// Reported from device: nine grid slots appeared and only four cars turned up. The
/// cap lived in three places and only two were named, so `startRace` quietly clamped
/// a solo player's field to three AI — the number the setup screen had already
/// accepted was then thrown away without a word.
@MainActor
struct FullFieldTests {
    @Test func everyRequestedCarActuallyStarts() {
        // Combinations within today's soft cap. The engine seats
        // `fieldCapacity` (9) and races it correctly; `maxCars` is the smaller
        // number the product currently offers — see `CouchGame.maxCars`.
        let cap = CouchGame.maxCars
        // AI is a toggle now, not a count: filling means "the rest of the grid", so the
        // expected field is the cap when filling and the human count when not.
        for (humans, fill) in [(1, true), (2, true), (cap, true), (1, false), (2, false)] {
            let game = CouchGame()
            game.playerCount = humans
            game.fillWithAI = fill
            game.startRace()
            let started = game.session?.race.cars.count ?? -1
            let expected = fill ? cap : humans
            #expect(
                started == expected,
                "\(humans) human, fill=\(fill) produced \(started) cars, wanted \(expected)")
        }
    }

    /// A solo player can face a **full** field — the case that was broken.
    @Test func oneHumanCanFillTheFieldWithAI() {
        let game = CouchGame()
        game.playerCount = 1
        game.fillWithAI = true
        game.startRace()
        #expect(game.session?.race.cars.count == CouchGame.maxCars)
    }

    /// Every car gets its own color, so the field is legible at the flag.
    @Test func aFullFieldHasNoRepeatedColors() {
        let game = CouchGame()
        game.playerCount = 1
        game.fillWithAI = true
        game.startRace()
        let colors = game.carColors
        #expect(colors.count == CouchGame.maxCars)
        #expect(
            Set(colors.map { String(describing: $0) }).count == colors.count,
            "two cars share a color")
    }

    /// **The soft cap is a product choice, not an engine limit.**
    ///
    /// `maxCars` is deliberately below what the grid and palette support, pending
    /// device performance numbers. These pin that the capability underneath is intact,
    /// so raising the cap stays a one-number change rather than a project.
    @Test func theEngineStillSeatsAFullNineCars() throws {
        #expect(CouchGame.fieldCapacity == PieceCompiler.Grid.slots)
        #expect(CarPalette.count >= CouchGame.fieldCapacity, "a color per slot")
        #expect(
            CouchGame.maxCars <= CouchGame.fieldCapacity,
            "the soft cap must not exceed what the grid can seat")

        // And a full field really races — driven here rather than assumed, since
        // nothing in the product exercises it while the cap is lower.
        let track = try #require(TrackLibrary.track(id: "eight"))
        var race = Race(
            track: track, players: (0..<CouchGame.fieldCapacity).map(PlayerID.init),
            config: RaceConfig(laps: 1))
        var drivers = (0..<CouchGame.fieldCapacity).map { _ in AIDriver() }
        for _ in 0..<(30 * Race.tickRate) {
            var inputs: [PlayerID: CarInput] = [:]
            for index in 0..<CouchGame.fieldCapacity {
                inputs[PlayerID(index)] = drivers[index].input(
                    car: race.cars[index].state, track: track)
            }
            race.advance(inputs: inputs)
            if race.cars.allSatisfy({ $0.progress.finishedAt != nil }) { break }
        }
        #expect(
            race.cars.allSatisfy { $0.progress.finishedAt != nil },
            "a full nine-car field must still complete a lap")
    }

    /// **The AI count can no longer be wrong, and this is why.**
    ///
    /// It used to be a number the setup screen offered and the race could refuse — the
    /// reported bug, in the other direction. Now it is derived from a toggle: filling
    /// means exactly the seats the people leave, whatever the player count is, so there
    /// is no value to clamp and nothing to disagree about.
    @Test func fillingTakesExactlyTheFreeSeats() {
        for humans in 1...CouchGame.maxLocalPlayers {
            let game = CouchGame()
            game.playerCount = humans
            game.fillWithAI = true
            #expect(
                game.aiCount == CouchGame.maxCars - humans,
                "with \(humans) humans, filling should take the \(CouchGame.maxCars - humans) free seats"
            )
            #expect(game.playerCount + game.aiCount == CouchGame.maxCars)
        }
    }
}
