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
    /// The buffer that absorbs everything jittery about a real link: delivery latency,
    /// packet loss repaired by the next packet, and — the one that forced this number
    /// up — a peer whose frame rate dips. A device drawn 40 times a second only
    /// publishes 40 times a second, so its input arrives in clumps no matter how the
    /// publish edge is computed; input cannot be sent while the app is not running.
    ///
    /// Two ticks (33 ms) left a 40 fps peer stalling the other on a third of its
    /// frames, measured. Six (100 ms) covers a frame gap plus delivery latency with
    /// room to spare. The cost is input lag, and that is a feel judgement that can
    /// only be made on a device — which is exactly what this knob is for.
    ///
    /// The host's value wins: it travels in `RaceStart`, so peers cannot disagree.
    public static var networkedDelayTicks = 6

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
        // **Colour by GLOBAL seat, so both devices agree.** Taking the first N of
        // this device's own picks gave every device the same first two colours —
        // both phones showed blue and orange, and no player could tell which car
        // was theirs. A seat number is the one thing every peer agrees on, so it is
        // what the colour hangs off.
        let rig = CouchRig(
            colorIndices: mySeats.map { $0.rawValue % Self.palette.count },
            schemes: Array(schemes.prefix(mySeats.count)),
            seating: SeatingConfig(faceToFace: faceToFace, openCorner: openCorner),
            // The seats these bands actually drive. Without this every device
            // builds players 0 and 1 and steers the host's cars.
            seats: mySeats)
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
            // Every value the SIM reads comes from the host's message. `carContact` is
            // physics, so a peer with it toggled the other way diverges on first touch.
            laps: start.laps, countdownTicks: 3 * Race.tickRate, carContact: start.carContact)
        // **Bands are found by seat, not by index.** Global seat numbers are sparse
        // — this device might drive seats 2 and 3 — so indexing the rig by
        // `rawValue` would read past its end. The rig's players now carry their real
        // seat numbers, so a lookup by seat is both correct and direct.
        let bandForSeat = Dictionary(
            uniqueKeysWithValues: localSeats.enumerated().map { ($1, $0) })
        let session = GameSession(
            track: track, players: start.roster.seats, config: config, seed: start.seed,
            // **The HOST's tuning, never this device's.** Every device used to race
            // with its own persisted panel values, so one nudged slider made the cars
            // physically different and the sims diverged immediately.
            tuning: start.tuning,
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

    /// Car colors in car order (humans first, then AI), for renderer + HUD.
    ///
    /// **Networked, colour comes from the seat.** This built the list from the LOCAL
    /// players, so on a guest driving seats 2–3 the array's first entry was seat 2's
    /// colour and every car on screen was painted as somebody else. A seat number is
    /// the one thing all peers agree on, so it is what the colour hangs off — and
    /// that also makes the two screens match, which is the point.
    public var carColors: [Color] {
        if let session, session.lockstep != nil {
            return session.race.cars.map { Self.palette[$0.id.rawValue % Self.palette.count] }
        }
        let humanColors = rig?.players.map(\.colorIndex) ?? Array(colorIndices.prefix(playerCount))
        return (humanColors + aiColorIndices).map { Self.palette[$0] }
    }
}
