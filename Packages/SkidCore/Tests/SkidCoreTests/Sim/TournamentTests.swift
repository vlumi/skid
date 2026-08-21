import Foundation
import Testing

@testable import SkidCore

/// **The tournament's rules, which are arithmetic and therefore testable.**
///
/// Scored per seat on the F1 table; everyone on the top score wins, by decision
/// — no tie-breaker, because a rule invented to separate two people who scored
/// the same is a rule nobody would remember.
struct TournamentTests {
    @Test func theTableIsTheOneEveryoneAlreadyKnows() {
        // F1's current points, which is the whole reason for choosing it: nobody
        // has to be taught the rule.
        #expect(Tournament.points(forPlace: 1) == 25)
        #expect(Tournament.points(forPlace: 2) == 18)
        #expect(Tournament.points(forPlace: 3) == 15)
        #expect(Tournament.points(forPlace: 4) == 12)
        #expect(Tournament.points(forPlace: 10) == 1)
        // Total rather than a precondition: past the table, and below it, score
        // nothing instead of trapping.
        #expect(Tournament.points(forPlace: 11) == 0)
        #expect(Tournament.points(forPlace: 0) == 0)
        #expect(Tournament.points(forPlace: -1) == 0)
        // The table must cover a full grid, or a ninth-place car would score
        // nothing for finishing.
        #expect(Tournament.pointsByPlace.count >= PieceCompiler.Grid.slots)
    }

    @Test func pointsAccumulateAcrossRaces() {
        var series = Tournament(trackIDs: ["a", "b"], seatCount: 4)
        series.record(order: [0, 1, 2, 3])
        #expect(series.pointsBySeat == [25, 18, 15, 12])
        series.record(order: [3, 2, 1, 0])
        #expect(series.pointsBySeat == [25 + 12, 18 + 15, 15 + 18, 12 + 25])
        #expect(series.standings == [0, 3, 1, 2], "equal scores must order by seat")
    }

    /// A car that never finished is simply not in the order — the series carries
    /// on and that seat scores nothing for the race.
    @Test func aSeatMissingFromAResultScoresNothingForIt() {
        var series = Tournament(trackIDs: ["a"], seatCount: 3)
        series.record(order: [2, 0])
        #expect(series.pointsBySeat == [18, 0, 25])
    }

    /// A stray index cannot corrupt the table — a result naming a seat outside
    /// the field is ignored rather than crashing.
    @Test func anOutOfRangeSeatIsIgnored() {
        var series = Tournament(trackIDs: ["a"], seatCount: 2)
        series.record(order: [0, 1, 7])
        #expect(series.pointsBySeat == [25, 18])
    }

    @Test func progressTracksTheRacesRun() {
        var series = Tournament(trackIDs: ["a", "b", "c", "d"], seatCount: 2)
        #expect(series.raceCount == 4)
        #expect(series.completedCount == 0)
        #expect(series.currentRaceNumber == 1)
        #expect(series.nextTrackID == "a")
        #expect(!series.isComplete)

        series.record(order: [0, 1])
        #expect(series.currentRaceNumber == 2)
        #expect(series.nextTrackID == "b")

        for _ in 0..<3 { series.record(order: [0, 1]) }
        #expect(series.isComplete)
        #expect(series.nextTrackID == nil, "a finished series has no next track")
        // And the race number stops at the length rather than running past it,
        // so the final results screen can still name the race that just ended.
        #expect(series.currentRaceNumber == 4)
    }

    /// A finished series refuses more results: a stray results screen must not
    /// be able to append a fifth race to a four-race tournament.
    @Test func aCompleteSeriesRecordsNothingMore() {
        var series = Tournament(trackIDs: ["a"], seatCount: 2)
        series.record(order: [0, 1])
        series.record(order: [1, 0])
        #expect(series.results.count == 1)
        #expect(series.pointsBySeat == [25, 18])
    }

    // MARK: - Winning, and sharing a win

    @Test func thereIsNoWinnerUntilTheSeriesIsOver() {
        var series = Tournament(trackIDs: ["a", "b"], seatCount: 2)
        #expect(series.winners.isEmpty, "an empty series has no winner")
        series.record(order: [0, 1])
        #expect(series.winners.isEmpty, "a leader mid-series is not a winner")
        series.record(order: [0, 1])
        #expect(series.winners == [0])
    }

    /// **A level series ends level.** Two seats on the same points both won —
    /// the decided rule, and the reason `standings` order is presentation only.
    @Test func everyoneOnTheTopScoreWins() {
        var series = Tournament(trackIDs: ["a", "b"], seatCount: 2)
        series.record(order: [0, 1])
        series.record(order: [1, 0])
        #expect(series.pointsBySeat == [25 + 18, 18 + 25])
        #expect(series.winners == [0, 1], "a tie is a shared win, not a tiebreak")
    }

    /// The extreme case, and the one the decision was made for: four people who
    /// took a win each all won.
    @Test func aFourWayTieIsAFourWayWin() {
        var series = Tournament(trackIDs: ["a", "b", "c", "d"], seatCount: 4)
        series.record(order: [0, 1, 2, 3])
        series.record(order: [1, 2, 3, 0])
        series.record(order: [2, 3, 0, 1])
        series.record(order: [3, 0, 1, 2])
        #expect(Set(series.pointsBySeat).count == 1, "the fixture is not actually level")
        #expect(series.winners == [0, 1, 2, 3])
    }

    // MARK: - Drawing the tracks

    @Test func aDrawIsDistinctWhileThePoolAllows() {
        let pool = ["a", "b", "c", "d", "e", "f"]
        let drawn = Tournament.draw(raceCount: 4, from: pool, seed: 7)
        #expect(drawn.count == 4)
        #expect(Set(drawn).count == 4, "a pool this size should not repeat")
        #expect(drawn.allSatisfy(pool.contains))
    }

    /// **A short pool gives a full series, not a short one.** Four races from a
    /// pool of three is four races — the built-in set is still small, so this is
    /// the normal case rather than an edge one.
    @Test func aShortPoolRepeatsRatherThanShorteningTheSeries() {
        let drawn = Tournament.draw(raceCount: 4, from: ["a", "b", "c"], seed: 3)
        #expect(drawn.count == 4)
        #expect(Set(drawn).count == 3, "every track in the pool should appear")
    }

    /// No track twice in a row, which is the one repeat a player notices.
    @Test func noTrackRunsTwiceInARow() {
        for seed in UInt64(0)..<40 {
            for poolSize in 2...5 {
                let pool = (0..<poolSize).map { "t\($0)" }
                let drawn = Tournament.draw(raceCount: 6, from: pool, seed: seed)
                for (a, b) in zip(drawn, drawn.dropFirst()) {
                    #expect(a != b, "seed \(seed), pool \(poolSize): \(drawn)")
                }
            }
        }
    }

    @Test func aDrawIsReproducibleFromItsSeed() {
        let pool = ["a", "b", "c", "d", "e"]
        let first = Tournament.draw(raceCount: 4, from: pool, seed: 99)
        #expect(Tournament.draw(raceCount: 4, from: pool, seed: 99) == first)
        // And a different seed generally gives a different order, or the seed
        // would not be doing anything.
        let others = (0..<20).map { Tournament.draw(raceCount: 4, from: pool, seed: $0) }
        #expect(others.contains { $0 != first })
    }

    @Test func aDegenerateDrawIsEmptyRatherThanACrash() {
        #expect(Tournament.draw(raceCount: 4, from: [], seed: 1).isEmpty)
        #expect(Tournament.draw(raceCount: 0, from: ["a"], seed: 1).isEmpty)
    }

    /// A one-track pool cannot avoid repeats, and must not spin trying.
    @Test func aSingleTrackPoolFillsTheSeries() {
        let drawn = Tournament.draw(raceCount: 4, from: ["only"], seed: 5)
        #expect(drawn == ["only", "only", "only", "only"])
    }

    @Test func aSeriesSurvivesEncoding() throws {
        var series = Tournament(trackIDs: ["a", "b"], seatCount: 3)
        series.record(order: [1, 0, 2])
        let back = try JSONDecoder().decode(
            Tournament.self, from: JSONEncoder().encode(series))
        #expect(back == series)
        #expect(back.pointsBySeat == series.pointsBySeat)
    }
}
