import SkidCore
import SwiftUI

/// **"Which car is mine?" — answered on the grid, before it matters.**
///
/// During the countdown every LOCAL player's car gets a ring in their color and a
/// numbered chip beside it, the number rotated to face its own player — the rig
/// already knows each seat's `up`, so the player across the table reads their
/// number as easily as the near one. Gone the moment the race starts: mid-race the
/// cars are moving and the colors carry identity; the grid is where four identical
/// silhouettes sit still in a row and a new player genuinely cannot tell.
struct GridMarker {
    /// The car's position, in screen points.
    var position: Vec2
    /// The owning player's zone `up`, so the number can face them.
    var up: Vec2
    /// The seat number, 1-based — matching the P1/P2 naming everywhere else.
    var number: Int
    var color: Color
}

enum GridMarkers {
    /// The markers for one frame — empty except during the countdown.
    @MainActor
    static func markers(
        race: Race, players: [PlayerControls], mapRect: CGRect, palette: [Color]
    ) -> [GridMarker] {
        guard case .countdown = race.phase else { return [] }
        let scale = mapRect.width / race.track.size.x
        return players.compactMap { controls in
            guard let car = race.cars.first(where: { $0.id == controls.player }) else {
                return nil
            }
            return GridMarker(
                position: Vec2(
                    mapRect.minX + car.state.position.x * scale,
                    mapRect.minY + car.state.position.y * scale),
                up: controls.up,
                number: controls.player.rawValue + 1,
                color: palette[controls.colorIndex % palette.count])
        }
    }
}
