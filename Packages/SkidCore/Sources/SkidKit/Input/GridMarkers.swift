import SkidCore
import SwiftUI

/// **"Which car is mine?" — answered on the grid, before it matters.**
///
/// During the countdown every LOCAL player's car sits on a round highlight of
/// their color, tethered by a thin leader line to their own control band —
/// follow the line from under your thumbs and it ends under your car. Gone the
/// moment the race starts: mid-race the cars are moving and the colors carry
/// identity; the grid is where four identical silhouettes sit still in a row and
/// a new player genuinely cannot tell.
///
/// Two designs died on device before this one. A ring-plus-numbered-chip per car
/// was four overlapping boxes covering the very cars they pointed at; arrows
/// fanning in from the roomiest side still lay across the grid, and a nine-car
/// field is three rows deep — there is nowhere near a packed grid to put
/// clutter. A halo is UNDER its own car (drawn translucent, so the car reads on
/// top of it) and reaches just past the slot, and the leader line is a hairline:
/// nothing covers anything, however dense the grid. A faint tint of the painted
/// grid box was considered too — the box is barely bigger than the car, so a
/// tint that fits inside it is too subtle to spot.
struct GridMarker {
    /// The car's position, in screen points — the halo's center.
    var position: Vec2
    /// Where the leader line leaves the player's control band: the middle of the
    /// band's map-side edge.
    var leaderStart: Vec2
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
            let position = Vec2(
                mapRect.minX + car.state.position.x * scale,
                mapRect.minY + car.state.position.y * scale)
            return GridMarker(
                position: position,
                leaderStart: mapEdge(of: controls),
                color: palette[controls.colorIndex % palette.count])
        }
    }

    /// The middle of the band's MAP-SIDE edge — `up` points from the player's own
    /// edge toward the map, so this is where a line to the track naturally leaves.
    @MainActor
    static func mapEdge(of controls: PlayerControls) -> Vec2 {
        let zone = controls.zone
        let center = Vec2(zone.midX, zone.midY)
        let halfSpan = controls.up.y != 0 ? zone.height / 2 : zone.width / 2
        return center + controls.up * halfSpan
    }
}
