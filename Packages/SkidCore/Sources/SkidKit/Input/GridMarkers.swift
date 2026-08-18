import SkidCore
import SwiftUI

/// **"Which car is mine?" — answered on the grid, before it matters.**
///
/// During the countdown every LOCAL player's car gets a stylized arrow in their
/// color pointing at it. Gone the moment the race starts: mid-race the cars are
/// moving and the colors carry identity; the grid is where four identical
/// silhouettes sit still in a row and a new player genuinely cannot tell.
///
/// An arrow, and nothing else. The first pass drew a ring around each car plus a
/// numbered chip — on a four-car grid that was four overlapping boxes covering the
/// very cars they pointed at (reported from device).
///
/// **All the arrows come from ONE side of the grid** — the roomiest gap between
/// the grid and the map's edge. Per-seat sides read nicely but break the moment a
/// start line sits near an edge, where somebody's arrow has no room to stand; an
/// arrow needs no orientation to be read, so the color alone says whose it is.
///
/// **And their tails spread out along a shared base line.** Four arrows aimed
/// straight along the approach at a two-by-two grid landed on top of each other —
/// the grid is a few car-widths across and an arrow is one. Each tail gets its own
/// spot (minimum one arrow-width apart, in grid order), and each arrow tilts from
/// its spot to its own car, like pit-board callouts.
struct GridMarker {
    /// The car's position, in screen points.
    var position: Vec2
    /// The arrow's tail center on the shared base line; the arrow points from
    /// here at the car.
    var anchor: Vec2
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
        let positioned: [(controls: PlayerControls, position: Vec2)] = players.compactMap { p in
            guard let car = race.cars.first(where: { $0.id == p.player }) else {
                return nil
            }
            let position = Vec2(
                mapRect.minX + car.state.position.x * scale,
                mapRect.minY + car.state.position.y * scale)
            return (p, position)
        }
        guard let first = positioned.first else { return [] }
        var grid = CGRect(origin: CGPoint(x: first.position.x, y: first.position.y), size: .zero)
        for entry in positioned.dropFirst() {
            grid = grid.union(
                CGRect(origin: CGPoint(x: entry.position.x, y: entry.position.y), size: .zero))
        }
        let direction = roomiestApproach(grid: grid, mapRect: mapRect)
        let anchors = spreadAnchors(
            positions: positioned.map(\.position), direction: direction)
        return zip(positioned, anchors).map { entry, anchor in
            GridMarker(
                position: entry.position,
                anchor: anchor,
                color: palette[entry.controls.colorIndex % palette.count])
        }
    }

    /// One arrow-width plus a sliver, so neighbouring tails can never touch.
    static let anchorSpacing = 30.0
    /// How far the base line sits behind the grid's rearmost car (against the
    /// approach direction).
    static let anchorSetback = 48.0

    /// Tail spots on the base line: each starts at its car's own lateral
    /// position, then the row is pushed apart to `anchorSpacing` and re-centered —
    /// so every arrow stays as near its car as its neighbours allow.
    static func spreadAnchors(positions: [Vec2], direction: Vec2) -> [Vec2] {
        let lateral = direction.perpendicular
        let base = positions.map { $0.dot(direction) }.min()! - anchorSetback
        let order = positions.indices.sorted {
            positions[$0].dot(lateral) < positions[$1].dot(lateral)
        }
        var spots = order.map { positions[$0].dot(lateral) }
        for index in 1..<spots.count {
            spots[index] = max(spots[index], spots[index - 1] + anchorSpacing)
        }
        let drift =
            (zip(order, spots).map { positions[$0].dot(lateral) - $1 }.reduce(0, +))
            / Double(spots.count)
        var anchors = [Vec2](repeating: .zero, count: positions.count)
        for (rank, index) in order.enumerated() {
            anchors[index] = lateral * (spots[rank] + drift) + direction * base
        }
        return anchors
    }

    /// The shared arrow direction: in from whichever map edge leaves the grid the
    /// most room, so a start line near an edge never pushes an arrow off the map.
    static func roomiestApproach(grid: CGRect, mapRect: CGRect) -> Vec2 {
        let rooms: [(room: Double, direction: Vec2)] = [
            (grid.minY - mapRect.minY, Vec2(0, 1)),  // from above, pointing down
            (mapRect.maxY - grid.maxY, Vec2(0, -1)),  // from below, pointing up
            (grid.minX - mapRect.minX, Vec2(1, 0)),  // from the left, pointing right
            (mapRect.maxX - grid.maxX, Vec2(-1, 0)),  // from the right, pointing left
        ]
        return rooms.max { $0.room < $1.room }?.direction ?? Vec2(0, -1)
    }
}
