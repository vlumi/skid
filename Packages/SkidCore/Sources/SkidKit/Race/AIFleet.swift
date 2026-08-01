import SkidCore
import SwiftUI

/// Mutable box for the AI drivers (their stuck-recovery memory mutates
/// tick to tick).
@MainActor
final class AIFleet {
    var drivers: [PlayerID: AIDriver] = [:]

    func input(for player: PlayerID, in race: Race) -> CarInput {
        guard var driver = drivers[player],
            race.cars.indices.contains(player.rawValue)
        else { return .coast }
        let input = driver.input(car: race.cars[player.rawValue].state, track: race.track)
        drivers[player] = driver
        return input
    }
}
