import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The series as the app runs it**: draw, race, score, advance, persist.
///
/// The rules are `TournamentTests`' job. This is the wiring — which is where the
/// bugs live: a results screen that scores the wrong race, a "next race" that
/// reruns the same track, a series a relaunch forgets.
@MainActor
final class TournamentFlowTests: XCTestCase {
    private var setupFilename = ""

    override func setUp() {
        super.setUp()
        setupFilename = "test-tournament-\(UUID().uuidString).json"
    }

    private func game() -> CouchGame {
        CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "test-tournament-\(UUID().uuidString).json",
            profileFilename: "test-tournament-\(UUID().uuidString).json",
            setupFilename: setupFilename)
    }

    func testTheDrawFillsTheSeriesFromTheAvailableTracks() {
        let couch = game()
        couch.drawTournamentTracks()
        XCTAssertEqual(couch.pendingTournamentTracks.count, CouchGame.tournamentRaces)
        XCTAssertTrue(
            couch.pendingTournamentTracks.allSatisfy(couch.tournamentPool.contains),
            "the draw produced a track that is not in the pool")
    }

    /// The pool is built-ins PLUS the player's own raceable tracks — the decided
    /// answer, since four built-ins alone would make every series the same.
    func testThePoolIncludesThePlayersOwnTracks() throws {
        let couch = game()
        let builtinCount = couch.tournamentPool.count
        XCTAssertEqual(builtinCount, TrackLibrary.builtins.count)
        // Put a raceable track in the library the way the editor would.
        let code = TrackLibrary.builtins[0].code
        var book = couch.library
        book.put(
            TrackLibraryBook.Entry(
                name: "Mine", code: code, isRaceable: true, createdAt: Date(),
                updatedAt: Date()))
        couch.library = book
        XCTAssertEqual(
            couch.tournamentPool.count, builtinCount + 1,
            "a raceable library track must be drawable")
    }

    /// Starting a series freezes its field and puts the first race's track up.
    func testStartingASeriesRacesItsFirstTrack() {
        let couch = game()
        couch.mode = .tournament
        couch.fillWithAI = true
        couch.drawTournamentTracks()
        let lineup = couch.pendingTournamentTracks
        couch.startTournament()

        let series = try? XCTUnwrap(couch.tournament)
        XCTAssertNotNil(series)
        XCTAssertEqual(couch.tournament?.trackIDs, lineup)
        XCTAssertEqual(couch.trackID, lineup[0], "the first race is not on the first track")
        XCTAssertEqual(couch.phase, .racing)
        // Every car scores, AI included — otherwise second place would read as a win.
        XCTAssertEqual(couch.tournament?.seatCount, couch.session?.race.cars.count)
    }

    /// **A finished race scores, and the next one runs the NEXT track.** The
    /// whole loop, which is what a player experiences as "the tournament works".
    func testEachRaceScoresAndAdvancesToTheNextTrack() throws {
        let couch = game()
        couch.mode = .tournament
        couch.drawTournamentTracks()
        couch.startTournament()
        let lineup = try XCTUnwrap(couch.tournament?.trackIDs)

        for race in 0..<CouchGame.tournamentRaces {
            XCTAssertEqual(
                couch.trackID, lineup[race], "race \(race + 1) is on the wrong track")
            let session = try XCTUnwrap(couch.session)
            couch.recordTournamentResult(session.race)
            XCTAssertEqual(
                couch.tournament?.completedCount, race + 1,
                "race \(race + 1) did not score")
            couch.advanceTournament()
        }
        XCTAssertEqual(couch.tournament?.isComplete, true)
        XCTAssertFalse(couch.tournament?.winners.isEmpty ?? true, "a finished series has a winner")
    }

    /// **Scoring twice must not happen**, and the results card is rebuilt freely
    /// by SwiftUI — so the guard is in the model, not in the view's lifecycle.
    func testAResultIsNotCountedTwice() throws {
        let couch = game()
        couch.mode = .tournament
        couch.drawTournamentTracks()
        couch.startTournament()
        let session = try XCTUnwrap(couch.session)
        couch.recordTournamentResult(session.race)
        let after = try XCTUnwrap(couch.tournament)
        // A second call for the SAME race must change nothing. The card scores
        // from `onAppear`, and SwiftUI may appear a view more than once — the
        // first version of this had no guard, and a redraw would have handed
        // somebody a phantom 25 points.
        couch.recordTournamentResult(session.race)
        couch.recordTournamentResult(session.race)
        XCTAssertEqual(
            couch.tournament, after, "the same race was scored more than once")
    }

    /// Outside a tournament, recording does nothing at all.
    func testASingleRaceScoresNothing() throws {
        let couch = game()
        couch.mode = .race
        couch.startRace()
        let session = try XCTUnwrap(couch.session)
        couch.recordTournamentResult(session.race)
        XCTAssertNil(couch.tournament)
    }

    /// A series survives quitting — the reported requirement for any series
    /// longer than one sitting.
    func testASeriesSurvivesARelaunch() throws {
        let before = game()
        before.mode = .tournament
        before.drawTournamentTracks()
        before.startTournament()
        let session = try XCTUnwrap(before.session)
        before.recordTournamentResult(session.race)
        let expected = try XCTUnwrap(before.tournament)

        let after = game()
        XCTAssertEqual(after.mode, .tournament)
        XCTAssertEqual(after.tournament, expected, "the series did not survive the relaunch")
        XCTAssertEqual(after.tournament?.completedCount, 1)
    }

    /// A series naming a track that no longer exists is dropped rather than
    /// restored onto a race that cannot start.
    func testASeriesReferencingAGoneTrackIsDropped() {
        var memory = SetupMemory(
            mode: .tournament, trackID: TrackLibrary.builtins[0].id,
            entrants: [.guest], schemes: [.casual, .casual, .casual, .casual],
            fillWithAI: true, aiDifficulty: .medium)
        memory.tournament = Tournament(
            trackIDs: ["no-such-track", TrackLibrary.builtins[0].id], seatCount: 2)
        SetupFile(filename: setupFilename).save(memory)
        XCTAssertNil(game().tournament)
    }

    func testQuittingASeriesClearsIt() {
        let couch = game()
        couch.mode = .tournament
        couch.drawTournamentTracks()
        couch.startTournament()
        XCTAssertNotNil(couch.tournament)
        couch.abandonTournament()
        XCTAssertNil(couch.tournament)
        XCTAssertEqual(couch.phase, .setup)
    }

    /// Swapping a row is how manual picking works — after a draw, or instead of one.
    func testATrackCanBeSwappedByHand() {
        let couch = game()
        couch.drawTournamentTracks()
        let replacement = TrackLibrary.builtins.last!.id
        couch.setTournamentTrack(replacement, atRace: 2)
        XCTAssertEqual(couch.pendingTournamentTracks[2], replacement)
        // Out of range is ignored rather than trapping or appending.
        let before = couch.pendingTournamentTracks
        couch.setTournamentTrack(replacement, atRace: 99)
        XCTAssertEqual(couch.pendingTournamentTracks, before)
    }

    /// "Reset all data" clears a series with everything else, so a relaunch
    /// after a reset is not still mid-tournament.
    func testResetAllDataClearsTheSeries() {
        let couch = game()
        couch.mode = .tournament
        couch.drawTournamentTracks()
        couch.startTournament()
        couch.resetAllData()
        XCTAssertNil(couch.tournament)
        XCTAssertTrue(couch.pendingTournamentTracks.isEmpty)
    }
}
