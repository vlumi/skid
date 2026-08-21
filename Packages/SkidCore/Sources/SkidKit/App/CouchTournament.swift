import SkidCore
import SwiftUI

/// **Running a series of races.**
///
/// A separate file from `CouchGame` because it is a distinct subject with the
/// same owner — and because that file sits at its length limit. The rules live in
/// `Tournament` (`SkidCore`, pure and tested); this is the app side: which tracks
/// the series draws from, when the next race starts, and where the standings go.
extension CouchGame {
    /// **Fixed at four races for now.** Selectable length (3/5/7) is planned, but
    /// a number nobody has driven yet is a worse default than one round of four,
    /// which is short enough to finish in a sitting and long enough that one bad
    /// race is not the end of it.
    public static let tournamentRaces = 4

    /// **What a series can draw from: every raceable track this device has.**
    ///
    /// Built-ins plus the player's own library. The built-in set is still small,
    /// so drawing only from it would make every random series the same four
    /// tracks — and a track somebody built is a track they want to race. A
    /// curation rule ("worth racing", beyond merely raceable) is wanted later;
    /// until it exists, everything raceable is in.
    public var tournamentPool: [String] {
        TrackLibrary.builtins.map(\.id) + library.tracks.filter(\.isRaceable).map(\.id)
    }

    /// A track's name for the series chrome, whichever kind of track it is.
    public func trackName(forID id: String) -> String {
        if let builtin = TrackLibrary.builtins.first(where: { $0.id == id }) {
            return builtin.name
        }
        return library.entry(id: id)?.name ?? String(localized: "Track", bundle: .module)
    }

    /// Draw a fresh set of tracks — the "random" answer, and the button that
    /// re-draws one you did not like.
    public func drawTournamentTracks() {
        seed += 1
        pendingTournamentTracks = Tournament.draw(
            raceCount: Self.tournamentRaces, from: tournamentPool, seed: seed)
        saveSetupMemory()
    }

    /// Replace one race's track by hand — the "or after random picking do
    /// changes" case, and the whole of manual picking: draw, then swap what you
    /// want. Ignored for a race outside the series.
    public func setTournamentTrack(_ id: String, atRace index: Int) {
        guard pendingTournamentTracks.indices.contains(index) else { return }
        pendingTournamentTracks[index] = id
        saveSetupMemory()
    }

    /// **Begin the series**, freezing its field and its tracks.
    ///
    /// The field is frozen because standings across races are meaningless if the
    /// competitors change mid-series — so the seat count is taken once, here.
    public func startTournament() {
        let tracks =
            pendingTournamentTracks.isEmpty
            ? Tournament.draw(
                raceCount: Self.tournamentRaces, from: tournamentPool, seed: seed)
            : pendingTournamentTracks
        guard !tracks.isEmpty else { return }
        pendingTournamentTracks = tracks
        // Every car scores, AI included: a series against the computer is a
        // series, and leaving the AI out of the table would make second place
        // read as a win.
        tournament = Tournament(trackIDs: tracks, seatCount: fieldSize)
        startTournamentRace()
    }

    /// How many cars the series scores — the same field every race, which is
    /// what freezing the tournament's `seatCount` means.
    var fieldSize: Int {
        let humans = playerCount
        let ai = fillWithAI ? min(aiCount, Self.maxCars - humans) : 0
        return humans + ai
    }

    /// Start (or restart) the race the series is currently on.
    public func startTournamentRace() {
        guard let next = tournament?.nextTrackID else { return }
        trackID = next
        startRace()
    }

    /// **Fold a finished race into the standings.** Called from the results card
    /// when it appears.
    ///
    /// **Idempotent per RACE, which it has to be**: the card calls this from
    /// `onAppear`, and SwiftUI may appear a view more than once — a second call
    /// would score the same race twice and hand somebody a phantom 25 points.
    /// Keyed on the session's `raceKey` (generation + seed, unique per race)
    /// rather than on a bool, so it also survives the card being rebuilt and
    /// stays correct across a rematch of the same track.
    public func recordTournamentResult(_ race: Race) {
        guard var series = tournament, !series.isComplete else { return }
        guard let key = session?.raceKey, key != scoredRaceKey else { return }
        scoredRaceKey = key
        series.record(order: race.standings)
        tournament = series
    }

    /// Move to the next race of the series. No-op once it is complete — the
    /// results screen shows the final standings instead.
    public func advanceTournament() {
        guard let series = tournament, !series.isComplete else { return }
        startTournamentRace()
    }

    /// Leave the series and go back to setup. The state is dropped rather than
    /// paused: a half-finished series kept around would silently resume days
    /// later on a screen that gave no hint it was mid-tournament.
    public func abandonTournament() {
        tournament = nil
        backToSetup()
    }
}
