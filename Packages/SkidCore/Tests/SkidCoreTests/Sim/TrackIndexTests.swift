import Foundation
import Testing

@testable import SkidCore

/// **The indexed track queries must answer EXACTLY what the full scan did.**
///
/// These are physics inputs: "how high is the road here", "am I on asphalt". A
/// query that differs by a hair changes how a car behaves, and under networking
/// two peers that disagree desync. So the index is not tested for plausibility
/// — it is compared against the exhaustive scan it replaces, over every track
/// the game ships plus the reporting 4-storey one, at thousands of points
/// including the places a car is never supposed to be.
struct TrackIndexTests {
    /// The reporting track: four climbing loops, storeys 0–3, fully walled.
    static let knot = [
        "AdUBFh96BAQEBAQEAnkEBBACBAQQAgQEEAECAwAIHAMFA0gDSAAIJwABAgME",
        "BQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJgUBBg",
    ].joined()

    private static func everyTrack() throws -> [Track] {
        var tracks = TrackLibrary.builtins.map { TrackLibrary.track(id: $0.id) }
        tracks.append(try PieceCompiler.compile(try TrackCode.decode(knot), id: "knot"))
        return tracks
    }

    // MARK: - The reference implementations, as they were before the index

    private func scanDistance(
        _ track: Track, _ p: Vec2, height: Double?, tolerance: Double
    ) -> Double {
        var best = Double.greatestFiniteMagnitude
        let count = track.centerline.count
        let anyGaps = track.gaps.contains(true)
        for i in track.centerline.indices {
            if let height, !track.segment(i, isAt: height, tolerance: tolerance) { continue }
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % count]
            guard anyGaps else {
                best = min(best, p.distance(toSegment: a, b))
                continue
            }
            if track.segmentIsGap(i) { continue }
            let cutStart = track.segmentIsGap((i - 1 + count) % count)
            let cutEnd = track.segmentIsGap((i + 1) % count)
            if cutStart || cutEnd {
                let along = b - a
                let lengthSquared = along.dot(along)
                if lengthSquared > 1e-9 {
                    let t = (p - a).dot(along) / lengthSquared
                    if cutStart, t < 0 { continue }
                    if cutEnd, t > 1 { continue }
                }
            }
            best = min(best, p.distance(toSegment: a, b))
        }
        return best
    }

    private func scanClosest(
        _ track: Track, _ p: Vec2, preferHeight: Double?, preferHeading: Double?
    ) -> (segment: Int, t: Double) {
        var best = (segment: 0, t: 0.0)
        var bestScore = Double.greatestFiniteMagnitude
        for i in track.centerline.indices {
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % track.centerline.count]
            let closest = p.closestPoint(onSegment: a, b)
            var score = p.distance(to: closest)
            if let preferHeight, !track.segment(i, isAt: preferHeight) { score += track.width }
            if let preferHeading {
                let along = b - a
                if along.length > 0 {
                    let travel = Vec2(angle: preferHeading)
                    score += track.width * (1 - abs(along.normalized.dot(travel)))
                }
            }
            if score < bestScore {
                bestScore = score
                let length = (b - a).length
                best = (i, length > 0 ? (closest - a).length / length : 0)
            }
        }
        return best
    }

    /// A deterministic sweep of probe points: a dense grid over the map, plus
    /// points well outside it (the editor and debug overlay ask about those).
    private func probes(for track: Track) -> [Vec2] {
        var points: [Vec2] = []
        let steps = 28
        for column in 0...steps {
            for row in 0...steps {
                points.append(
                    Vec2(
                        track.size.x * Double(column) / Double(steps),
                        track.size.y * Double(row) / Double(steps)))
            }
        }
        // Off the map in every direction, and right on the boundaries.
        for offset in [-500.0, -1.0, 0.0, 1.0] {
            points.append(Vec2(offset, offset))
            points.append(Vec2(track.size.x - offset, track.size.y - offset))
            points.append(Vec2(track.size.x / 2, offset))
            points.append(Vec2(offset, track.size.y / 2))
        }
        // And exactly on centerline points, where ties are most likely.
        for point in stride(from: 0, to: track.centerline.count, by: 5) {
            points.append(track.centerline[point])
        }
        return points
    }

    @Test func distanceToCenterlineMatchesTheFullScan() throws {
        for track in try Self.everyTrack() {
            for p in probes(for: track) {
                #expect(
                    track.distanceToCenterline(p)
                        == scanDistance(
                            track, p, height: nil, tolerance: Track.surfaceTolerance),
                    "\(track.id) at \(p)")
                // And with a height filter, at every storey the track uses.
                for level in 0...3 {
                    let height = Double(level) * Track.levelHeight
                    #expect(
                        track.distanceToCenterline(p, height: height)
                            == scanDistance(
                                track, p, height: height, tolerance: Track.surfaceTolerance),
                        "\(track.id) at \(p) height \(height)")
                }
            }
        }
    }

    @Test func closestCenterlinePointMatchesTheFullScan() throws {
        for track in try Self.everyTrack() {
            for p in probes(for: track) {
                let plain = track.closestCenterlinePoint(to: p)
                let reference = scanClosest(track, p, preferHeight: nil, preferHeading: nil)
                #expect(plain == reference, "\(track.id) at \(p)")
                for level in 0...2 {
                    let height = Double(level) * Track.levelHeight
                    #expect(
                        track.closestCenterlinePoint(to: p, preferHeight: height)
                            == scanClosest(
                                track, p, preferHeight: height, preferHeading: nil),
                        "\(track.id) at \(p) prefer \(height)")
                }
                for heading in [0.0, 1.2, 3.5] {
                    #expect(
                        track.closestCenterlinePoint(to: p, preferHeading: heading)
                            == scanClosest(
                                track, p, preferHeight: nil, preferHeading: heading),
                        "\(track.id) at \(p) heading \(heading)")
                }
            }
        }
    }

    /// The derived answers every caller actually uses, compared as bit patterns:
    /// a hair's difference in road height is a different physics input.
    @Test func theDerivedQueriesAreUnchanged() throws {
        for track in try Self.everyTrack() {
            for p in probes(for: track) {
                let reference = scanClosest(track, p, preferHeight: nil, preferHeading: nil)
                let next = (reference.segment + 1) % track.centerline.count
                let from = track.height(ofPoint: reference.segment)
                let to = track.height(ofPoint: next)
                let expected = from + (to - from) * reference.t
                #expect(
                    track.height(at: p).bitPattern == expected.bitPattern,
                    "height at \(p) on \(track.id)")
                let onRoad =
                    scanDistance(track, p, height: 0, tolerance: Track.surfaceTolerance)
                    <= track.halfWidth(atHeight: 0)
                let hasPatch = track.patches.contains {
                    abs($0.height) <= Track.surfaceTolerance
                        && p.distance(to: $0.center) <= $0.radius
                }
                if !hasPatch {
                    #expect(
                        (track.surface(at: p) == .asphalt) == onRoad,
                        "surface at \(p) on \(track.id)")
                }
            }
        }
    }

    @Test func isOnRampIsUnchanged() throws {
        for track in try Self.everyTrack() {
            for p in probes(for: track) {
                var expected = false
                for i in track.centerline.indices {
                    let next = (i + 1) % track.centerline.count
                    let low = track.height(ofPoint: i)
                    let high = track.height(ofPoint: next)
                    guard abs(low - high) > 0.001 else { continue }
                    let reach = track.halfWidth(atHeight: max(low, high)) + 10
                    guard
                        p.distance(toSegment: track.centerline[i], track.centerline[next])
                            <= reach
                    else { continue }
                    expected = true
                    break
                }
                #expect(track.isOnRamp(p) == expected, "isOnRamp at \(p) on \(track.id)")
            }
        }
    }

    /// **A whole race must be bit-identical.** The queries feed the physics, so
    /// determinism across the change is the property that matters most: a replay,
    /// a ghost and a networked peer all depend on it.
    @Test func aDrivenRaceIsDeterministicWithTheIndex() throws {
        let track = try PieceCompiler.compile(try TrackCode.decode(Self.knot), id: "knot")
        let players = (0..<4).map(PlayerID.init)
        var first = Race(track: track, players: players, seed: 7, config: RaceConfig(laps: 2))
        var second = Race(track: track, players: players, seed: 7, config: RaceConfig(laps: 2))
        var ai = (0..<4).map { _ in AIDriver() }
        for _ in 0..<1_800 {
            var inputs: [PlayerID: CarInput] = [:]
            for (index, player) in players.enumerated() {
                inputs[player] = ai[index].input(car: first.cars[index].state, track: track)
            }
            first.advance(inputs: inputs)
            second.advance(inputs: inputs)
        }
        #expect(first.stateHash == second.stateHash)
        // The cars actually moved and stayed on the road — a race that crashed
        // into a wall on tick 1 would pass the comparison above vacuously.
        let moved = first.cars.contains { !$0.progress.lapTimes.isEmpty }
        #expect(moved, "no car completed a lap — the fixture proves nothing")
    }

    /// **A tie must name the same segment the full scan would** — the LOWEST
    /// index of the equally-close ones.
    ///
    /// Two segments meeting at a shared point are exactly equidistant from it,
    /// and that point is on the racing line, so a car sits there every lap. If
    /// the index reported the later segment instead, `arcPosition` would jump
    /// backwards by a segment at every joint and the standings would flicker.
    /// Sabotaging the tie rule alone left every other test in this file green,
    /// so it needs its own.
    @Test func aTieNamesTheLowestSegmentLikeTheScanDoes() throws {
        for track in try Self.everyTrack() {
            for index in stride(from: 1, to: track.centerline.count, by: 7) {
                // The shared endpoint of segments `index - 1` and `index`.
                let joint = track.centerline[index]
                let nearest = track.segmentIndex.nearest(
                    to: joint, centerline: track.centerline)
                var expected = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for i in track.centerline.indices {
                    let a = track.centerline[i]
                    let b = track.centerline[(i + 1) % track.centerline.count]
                    let distance = joint.distance(toSegment: a, b)
                    if distance < bestDistance {
                        bestDistance = distance
                        expected = i
                    }
                }
                let got = nearest?.segment ?? -1
                #expect(
                    got == expected,
                    "tie at joint \(index) of \(track.id): index says \(got), scan \(expected)")
            }
        }
    }

    /// A track that shares an id with another (ad-hoc test tracks all use "")
    /// must not read the wrong index.
    @Test func twoTracksSharingAnIdKeepTheirOwnIndex() {
        let straight = Track(
            centerline: [Vec2(100, 100), Vec2(100, 900)], width: 120,
            size: Vec2(1_000, 1_000))
        let elsewhere = Track(
            centerline: [Vec2(900, 100), Vec2(900, 900)], width: 120,
            size: Vec2(1_000, 1_000))
        #expect(straight.surface(at: Vec2(100, 500)) == .asphalt)
        #expect(elsewhere.surface(at: Vec2(100, 500)) == .grass)
        #expect(elsewhere.surface(at: Vec2(900, 500)) == .asphalt)
        #expect(straight.surface(at: Vec2(900, 500)) == .grass)
    }
}
