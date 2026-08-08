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
        for (humans, ai) in [(1, cap - 1), (2, cap - 2), (cap, 0), (1, 0), (2, 2)] {
            let game = CouchGame()
            game.playerCount = humans
            game.aiCount = ai
            game.startRace()
            let started = game.session?.race.cars.count ?? -1
            #expect(
                started == humans + ai,
                "\(humans) human + \(ai) AI produced \(started) cars")
        }
    }

    /// A solo player can face a **full** field — the case that was broken.
    @Test func oneHumanCanFillTheFieldWithAI() {
        let game = CouchGame()
        game.playerCount = 1
        game.aiCount = CouchGame.maxCars - 1
        game.startRace()
        #expect(game.session?.race.cars.count == CouchGame.maxCars)
    }

    /// Every car gets its own colour, so the field is legible at the flag.
    @Test func aFullFieldHasNoRepeatedColours() {
        let game = CouchGame()
        game.playerCount = 1
        game.aiCount = CouchGame.maxCars - 1
        game.startRace()
        let colours = game.carColors
        #expect(colours.count == CouchGame.maxCars)
        #expect(
            Set(colours.map { String(describing: $0) }).count == colours.count,
            "two cars share a colour")
    }

    /// **The soft cap is a product choice, not an engine limit.**
    ///
    /// `maxCars` is deliberately below what the grid and palette support, pending
    /// device performance numbers. These pin that the capability underneath is intact,
    /// so raising the cap stays a one-number change rather than a project.
    @Test func theEngineStillSeatsAFullNineCars() throws {
        #expect(CouchGame.fieldCapacity == PieceCompiler.Grid.slots)
        #expect(CarPalette.count >= CouchGame.fieldCapacity, "a colour per slot")
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

    /// The setup screen must not offer a number the race then refuses — that is the
    /// shape of the reported bug, in the other direction.
    @Test func theOfferedAICountIsTheRaceableOne() {
        for humans in 1...CouchGame.maxLocalPlayers {
            let game = CouchGame()
            game.playerCount = humans
            game.aiCount = CouchGame.maxCars  // deliberately over the top
            #expect(
                game.aiCount == CouchGame.maxCars - humans,
                "with \(humans) humans the AI count should clamp to the free seats")
        }
    }
}
