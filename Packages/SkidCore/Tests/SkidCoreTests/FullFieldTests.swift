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
        for (humans, ai) in [(1, 8), (2, 7), (3, 6), (4, 5), (1, 0), (2, 2)] {
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
    @Test func oneHumanCanRaceEightAI() {
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
