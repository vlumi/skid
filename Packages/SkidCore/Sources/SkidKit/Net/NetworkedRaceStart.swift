import SkidCore
import SwiftUI

/// **Starting a race whose inputs arrive off the wire.**
///
/// Split from `CouchGame` because it is a different concern with the same owner:
/// the couch path seats every player at one screen, while this one seats only the
/// people at THIS screen and lets the rest arrive as packets. The split also keeps
/// `CouchGame` inside the 450-line file limit.
extension CouchGame {
    /// Laps in a networked race. Fixed for now: the lobby has no lap picker, and
    /// a mismatch between peers would be a silent desync rather than a short race.
    public static let networkedLaps = 3

    /// **How far behind the newest input a networked race runs.**
    ///
    /// Two ticks is 33 ms of input lag. This is the single knob the spike exists to
    /// tune, and it can only be judged on a device by feel: the drift model is
    /// twitchy, so what is invisible in a slower game may not be here. 0 is
    /// legal (least lag, least tolerance for a late packet); 4 is 66 ms.
    ///
    /// The host's value wins — it travels in `RaceStart`, so peers cannot disagree.
    public static var networkedDelayTicks = 2

    /// Open the host/join lobby for a networked race.
    public func openNetworking() {
        phase = .networking
    }

    /// **Start a race whose inputs come off the wire.**
    ///
    /// The difference from `startRace()` is which seats get a control band: the
    /// `rig` lays out only the seats THIS device drives, while the sim carries
    /// every car in the roster. No AI — a networked field is people.
    ///
    /// The seed and the track come from the host, so both devices build the same
    /// `Race`. Getting either wrong would be a divergence at tick 1, which is
    /// exactly what the hash comparison would report.
    public func startNetworkedRace(_ start: RaceStart, driver: GameSession.LockstepDriver) {
        let track: Track
        switch start.course {
        case .builtin(let id):
            track = TrackLibrary.track(id: id)
        case .shared(let code):
            // A guest may never have seen this track — carrying the share code
            // rather than a track id is what makes that work. A code this device
            // cannot decode means the peers disagree about the course, so refusing
            // to start is the honest outcome: racing a different track would show
            // up as a tick-1 desync.
            guard let layout = try? TrackCode.decode(code),
                let compiled = try? PieceCompiler.compile(layout, id: "shared")
            else { return }
            track = compiled
        }
        let mySeats = driver.mySeats
        aiFleet.drivers = [:]
        // Local seats get the palette colours they picked; every other car is
        // coloured by its seat, which both devices agree on via the roster.
        let rig = CouchRig(
            colorIndices: Array(colorIndices.prefix(mySeats.count)),
            schemes: Array(schemes.prefix(mySeats.count)),
            seating: SeatingConfig(faceToFace: faceToFace, openCorner: openCorner))
        self.rig = rig
        let session = makeNetworkedSession(track: track, start: start, localSeats: mySeats)
        session.lockstep = driver
        self.session = session
        phase = .racing
    }

    private func makeNetworkedSession(
        track: Track, start: RaceStart, localSeats: [PlayerID]
    ) -> GameSession {
        let config = RaceConfig(
            laps: start.laps, countdownTicks: 3 * Race.tickRate, carContact: carContact)
        // **Local seats map to control bands by POSITION, not by seat number.**
        // Global seat numbers are sparse — this device might drive seats 2 and 3 —
        // so indexing the rig by `rawValue` would read past its end. The rig has
        // one band per local player, in the order the roster lists them.
        let bandForSeat = Dictionary(
            uniqueKeysWithValues: localSeats.enumerated().map { ($1, $0) })
        let session = GameSession(
            track: track, players: start.roster.seats, config: config, seed: start.seed,
            tuning: settings.carTuning,
            inputFor: { [weak rig] player, race in
                guard let band = bandForSeat[player], let rig,
                    rig.players.indices.contains(band)
                else { return .coast }
                let controls = rig.players[band]
                let source = controls.source(for: controls.scheme)
                if let headingAware = source as? HeadingAwareControlSource,
                    let car = race.cars.first(where: { $0.id == player })
                {
                    headingAware.setCar(
                        heading: car.state.heading,
                        forwardSpeed: car.state.velocity.dot(car.state.forward),
                        speed: car.state.velocity.length)
                }
                return source.input(for: player, at: race.tick)
            })
        return session
    }
}
