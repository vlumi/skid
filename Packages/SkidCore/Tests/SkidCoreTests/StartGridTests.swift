import Foundation
import Testing

@testable import SkidCore

/// **The start grid, up to nine cars.** Rows fill front-first and never widen, and
/// no two cars share an arc position — standings rank by distance along the
/// centerline, so a tie there hands pole order to an index tie-break.
struct StartGridTests {
    private typealias Grid = PieceCompiler.Grid

    /// The distributions, as decided: 2-abreast while the field fits in two rows,
    /// then 3-abreast front-loaded.
    @Test func rowsFillFrontFirstAndNeverWiden() {
        let expected: [Int: [Int]] = [
            1: [1], 2: [2], 3: [2, 1], 4: [2, 2], 5: [3, 2],
            6: [3, 3], 7: [3, 3, 1], 8: [3, 3, 2], 9: [3, 3, 3],
        ]
        for (count, rows) in expected {
            #expect(Grid.rows(for: count) == rows, "\(count) cars")
        }
        // And the rule those all obey, for any count.
        for count in 1...Grid.slots {
            let rows = Grid.rows(for: count)
            #expect(rows.reduce(0, +) == count, "\(count) cars: rows must seat everyone")
            for i in 1..<max(1, rows.count) {
                #expect(
                    rows[i] <= rows[i - 1], "\(count) cars: row \(i) is wider than the one ahead")
            }
        }
    }

    /// **Four cars stay 2:2**, not 3:1 — two abreast leaves 68 units between cars
    /// against three abreast's 24, and 3:1 would strand the fourth alone behind a
    /// full row. Four is also the commonest couch case.
    @Test func fourCarsKeepTheRoomyPairs() {
        #expect(Grid.rows(for: 4) == [2, 2])
    }

    /// The whole grid fits on the start piece, which is a 2U straight.
    @Test func theGridFitsTheStartPiece() {
        #expect(Grid.depth <= Double(PieceCatalog.straight), "grid is \(Grid.depth) deep")
    }

    /// **No two cars share an arc position.** This is not cosmetic: `raceProgress`
    /// measures distance along the centerline, so cars perfectly abreast tie and the
    /// ranking falls back to an index tie-break — which read as a random order at the
    /// lights when rows were introduced.
    @Test func everyCarHasItsOwnPlaceOnTheGrid() throws {
        let track = try #require(TrackLibrary.track(id: "clover"))
        for count in [4, 6, 9] {
            let race = Race(
                track: track, players: (0..<count).map(PlayerID.init),
                config: RaceConfig(laps: 3))
            let scores = race.cars.map { race.raceProgress(of: $0) }
            #expect(
                Set(scores).count == count,
                "\(count) cars produced only \(Set(scores).count) distinct grid positions")
        }
    }

    /// Every slot is on the asphalt, at every count — the outermost car of a 3-row
    /// sits 44 from the centerline against a 60 half-width.
    @Test func everySlotIsOnTheRoad() throws {
        for id in TrackLibrary.builtins.map(\.id) {
            let track = try #require(TrackLibrary.track(id: id))
            #expect(track.startSlots.count == Grid.slots, "\(id)")
            for (index, slot) in track.startSlots.enumerated() {
                #expect(
                    track.surface(at: slot, height: track.startHeight) == .asphalt,
                    "\(id) slot \(index) is off the road")
            }
        }
    }

    /// Pole is at the front: the first slot is nearest the line.
    @Test func poleIsNearestTheLine() throws {
        let track = try #require(TrackLibrary.track(id: "eight"))
        let line = try #require(track.gates.last)
        let midLine = (line.a + line.b) * 0.5
        let toLine = track.startSlots.map { $0.distance(to: midLine) }
        #expect(toLine[0] == toLine.min(), "slot 0 should be pole")
    }
}
