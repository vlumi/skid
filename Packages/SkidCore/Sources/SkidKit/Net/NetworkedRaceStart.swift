import SkidCore
import SwiftUI

/// What a networked race needs from the network, both roles in one protocol so
/// the start path takes a single object. A host uses the top half and ignores
/// the client half; a client the reverse. `NetworkedGame` conforms.
@MainActor
public protocol NetworkedRaceDriver: GameSession.SnapshotClientDriver {
    /// Whether this device simulates the race (true) or renders it (false).
    var isRaceHost: Bool { get }
    /// Host: the freshest input a remote seat has sent — held between packets.
    func remoteInput(for seat: PlayerID) -> CarInput
    /// Host: called after every simulated tick; the driver decides which ticks
    /// actually put a snapshot on the wire.
    func broadcast(_ race: Race)
}

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

    /// Open the host/join lobby for a networked race.
    public func openNetworking() {
        phase = .networking
    }

    /// **Start a race driven over the network — host or client.**
    ///
    /// The host is local play wearing a different input source: its sim carries
    /// every car in the roster, remote seats read `driver.remoteInput`, and every
    /// tick is offered to `driver.broadcast`. A client never simulates at all —
    /// its session gets `snapshotClient` and its race value becomes a display
    /// buffer for the host's snapshots.
    ///
    /// Either way the `rig` lays out only the seats THIS device drives, and no AI
    /// joins — a networked field is people.
    public func startNetworkedRace(_ start: RaceStart, driver: NetworkedRaceDriver) {
        // **Release every held touch before the rig is replaced.** A client is not
        // asked whether it wants the next race — it simply receives a `RaceStart`,
        // possibly with a thumb still down from the last one. The old rig's controls
        // keep that touch, and the new rig never sees the finger lift, so the visible
        // pad drives nothing. Local `raceAgain` has always done this; the networked
        // path did not, and the client's controls went dead after a rematch.
        // Reported from device.
        rig?.players.forEach { $0.releaseAll() }
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
        // **Color from the ROSTER, so both devices agree.** Taking the first N of
        // this device's own picks gave every device the same first two colors —
        // both phones showed blue and orange, and no player could tell which car
        // was theirs. The roster's resolved claims (first-come, host first; see
        // `RaceRoster.join`) are the one color story every peer holds, so they are
        // what the color hangs off — falling back to seat-number colors for a
        // roster from a build that predates claims.
        let rig = CouchRig(
            colorIndices: mySeats.map { start.roster.colorIndex(forSeat: $0) },
            schemes: Array(schemes.prefix(mySeats.count)),
            seating: SeatingConfig(faceToFace: faceToFace, openCorner: openCorner),
            // The seats these bands actually drive. Without this every device
            // builds players 0 and 1 and steers the host's cars.
            seats: mySeats)
        self.rig = rig
        let session = makeNetworkedSession(
            track: track, start: start, localSeats: mySeats, driver: driver)
        session.isNetworked = true
        // The whole field's colors, for the renderer + HUD (`carColors`) — same
        // source as the rig's, so this device's pads match its cars.
        session.seatColorIndices = Dictionary(
            uniqueKeysWithValues: start.roster.seats.map {
                ($0, start.roster.colorIndex(forSeat: $0))
            })
        // Stamped with the race it belongs to, so a session left on screen by a
        // rematch stops driving the shared client view.
        session.generation = driver.generation
        // The lobby's "Start race" is the shared ready gate — a per-device tap
        // deadlocked the countdown once already under lockstep, and under a host
        // authority a client has no sim to hold back anyway.
        session.started = true
        let humans = mySeats.count
        if driver.isRaceHost {
            session.onTick = { [weak self] race in
                driver.broadcast(race)
                self?.playRaceAudio(race, humans: humans, events: true)
            }
        } else {
            session.snapshotClient = driver
            // **Sound yes, haptics no.** Engine noise reads off the cars' state, which
            // a snapshot carries — so a client sounds right. Haptics fire off
            // `lastEvents` (impacts, laps), and a client has none: it renders the
            // host's state rather than simulating, so no event ever happens locally.
            // Sending events would mean putting them on the wire, which is more than
            // a rumble is worth right now.
            session.onTick = { [weak self] race in
                self?.playRaceAudio(race, humans: humans, events: false)
            }
        }
        self.session = session
        phase = .racing
    }

    private func makeNetworkedSession(
        track: Track, start: RaceStart, localSeats: [PlayerID], driver: NetworkedRaceDriver
    ) -> GameSession {
        // Every value the SIM reads comes from the host's message.
        let config = RaceConfig(laps: start.laps, countdownTicks: 3 * Race.tickRate)
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
            inputFor: { [weak rig, weak driver] player, race in
                guard let band = bandForSeat[player], let rig,
                    rig.players.indices.contains(band)
                else {
                    // Not one of this device's seats: on the host that is a remote
                    // player's car, and its input is whatever they sent last. On a
                    // client this path never runs — only local seats are read.
                    return driver?.remoteInput(for: player) ?? .coast
                }
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

    /// Engine sound, and haptics only where events exist. A networked race was
    /// silent, which reads as broken.
    private func playRaceAudio(_ race: Race, humans: Int, events: Bool) {
        if settings.soundOn {
            sound.update(race: race, humanCount: humans, paused: false)
        }
        if events, settings.hapticsOn {
            haptics.play(events: race.lastEvents, humanCount: humans)
        }
    }

    /// Car colors in car order (humans first, then AI), for renderer + HUD.
    ///
    /// **Networked, color comes from the roster's claims** (via the session's
    /// seat map). This built the list from the LOCAL players, so on a guest
    /// driving seats 2–3 the array's first entry was seat 2's color and every
    /// car on screen was painted as somebody else. The roster is the one color
    /// story all peers hold, so it is what the color hangs off — and that also
    /// makes the two screens match, which is the point.
    public var carColors: [Color] {
        if let session, session.isNetworked {
            return session.race.cars.map {
                Self.palette[
                    session.seatColorIndices[$0.id] ?? $0.id.rawValue % Self.palette.count]
            }
        }
        let humanColors = rig?.players.map(\.colorIndex) ?? Array(colorIndices.prefix(playerCount))
        return (humanColors + aiColorIndices).map { Self.palette[$0] }
    }
}
