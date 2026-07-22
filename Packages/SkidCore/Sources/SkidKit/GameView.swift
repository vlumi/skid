import SkidCore
import SwiftUI

/// Mutable box for the AI drivers (their stuck-recovery memory mutates
/// tick to tick).
@MainActor
final class AIFleet {
    var drivers: [PlayerID: AIDriver] = [:]

    func input(for player: PlayerID, in race: Race) -> CarInput {
        guard var driver = drivers[player],
            race.cars.indices.contains(player.rawValue)
        else { return .coast }
        let input = driver.input(car: race.cars[player.rawValue].state, track: race.track)
        drivers[player] = driver
        return input
    }
}

/// Top-level couch-game state: setup → race/time-trial → (results) → again.
@MainActor
public final class CouchGame: ObservableObject {
    public enum Phase {
        case setup
        case racing
    }

    public enum Mode: CaseIterable {
        case race
        case timeTrial
    }

    static let palette: [Color] = TrackRenderer.carPalette

    @Published public private(set) var phase: Phase = .setup
    @Published public var mode: Mode = .race
    @Published public var playerCount = 1 {
        didSet { aiCount = min(aiCount, 4 - playerCount) }
    }
    @Published public var aiCount = 0
    @Published public var aiDifficulty: AIDriver.Difficulty = .medium
    @Published public private(set) var colorIndices = [0, 1, 2, 3]
    @Published public var carContact = true
    /// 2P seating: side-by-side vs face-to-face.
    @Published public var faceToFace = false
    /// 3P seating: which quadrant stays open.
    @Published public var openCorner: ZoneCorner = .topLeft

    @Published public private(set) var session: GameSession?
    public private(set) var rig: CouchRig?
    public private(set) var hiscores: HiscoreBook

    private let hiscoreFile = HiscoreFile()
    private let aiFleet = AIFleet()
    private var aiColorIndices: [Int] = []
    private var seed: UInt64 = 1
    private var notedLapCount = 0
    private var notedFinish = false

    public init() {
        hiscores = hiscoreFile.load()
        // Dev affordance for automated screenshots/tests: launch straight
        // into a race (`-skid-players N -skid-autostart`).
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-skid-players"),
            index + 1 < arguments.count, let count = Int(arguments[index + 1])
        {
            playerCount = max(1, min(4, count))
        }
        if let index = arguments.firstIndex(of: "-skid-ai"),
            index + 1 < arguments.count, let count = Int(arguments[index + 1])
        {
            aiCount = max(0, min(4 - playerCount, count))
        }
        if arguments.contains("-skid-autostart") {
            startRace()
        }
    }

    /// Cycle one player's color to the next not taken by anyone else.
    public func cycleColor(slot: Int) {
        guard colorIndices.indices.contains(slot) else { return }
        let taken = Set(colorIndices.enumerated().filter { $0.offset != slot }.map(\.element))
        var next = colorIndices[slot]
        repeat {
            next = (next + 1) % Self.palette.count
        } while taken.contains(next)
        colorIndices[slot] = next
    }

    public func startRace() {
        let humans = mode == .timeTrial ? 1 : playerCount
        let ai = mode == .timeTrial ? 0 : min(aiCount, 4 - humans)
        let humanColors = Array(colorIndices.prefix(humans))
        // AI cars take the next free palette colors.
        var free = (0..<Self.palette.count).filter { !humanColors.contains($0) }
        aiColorIndices = Array(free.prefix(ai))
        free.removeFirst(min(ai, free.count))

        let seating = SeatingConfig(faceToFace: faceToFace, openCorner: openCorner)
        let rig = CouchRig(
            colorIndices: humanColors, scheme: rig?.scheme ?? .dpad, seating: seating)
        self.rig = rig
        aiFleet.drivers = Dictionary(
            uniqueKeysWithValues: (0..<ai).map {
                (PlayerID(humans + $0), AIDriver.make(aiDifficulty, gridIndex: $0))
            })
        seed += 1
        session = makeSession(humans: humans, totalCars: humans + ai)
        phase = .racing
    }

    public func raceAgain() {
        guard let rig else { return }
        for player in rig.players {
            player.releaseAll()
        }
        let humans = rig.players.count
        for (offset, player) in aiFleet.drivers.keys.sorted().enumerated() {
            aiFleet.drivers[player] = AIDriver.make(aiDifficulty, gridIndex: offset)
        }
        seed += 1
        session = makeSession(humans: humans, totalCars: humans + aiFleet.drivers.count)
    }

    public func backToSetup() {
        phase = .setup
        session = nil
        rig = nil
    }

    private func makeSession(humans: Int, totalCars: Int) -> GameSession {
        let players = (0..<totalCars).map { PlayerID($0) }
        let config: RaceConfig
        switch mode {
        case .race:
            config = RaceConfig(
                laps: 3, countdownTicks: 3 * Race.tickRate, carContact: carContact)
        case .timeTrial:
            // No finish line — lap forever, chase the best lap.
            config = RaceConfig(laps: nil, countdownTicks: 3 * Race.tickRate)
        }
        let ghost: GhostPlayback? =
            mode == .timeTrial
            ? GhostPlayback(
                record: hiscores.best(for: TrackLibrary.practiceLoop().id),
                track: TrackLibrary.practiceLoop())
            : nil
        notedLapCount = 0
        notedFinish = false
        let rig = self.rig
        let fleet = aiFleet
        let inputFor: (PlayerID, Race) -> CarInput = { [weak rig] player, race in
            if player.rawValue < humans {
                guard let rig, rig.players.indices.contains(player.rawValue) else {
                    return .coast
                }
                let controls = rig.players[player.rawValue]
                return controls.source(for: rig.scheme).input(for: player, at: race.tick)
            }
            return fleet.input(for: player, in: race)
        }
        return GameSession(
            players: players, config: config, seed: seed, ghost: ghost, inputFor: inputFor)
    }

    /// Called every frame by the race screen: fold the (single) human's
    /// results into the hiscores as they happen. Multi-human races don't
    /// record — hiscores are personal.
    public func noteProgress() {
        guard let session, let rig, rig.players.count == 1 else { return }
        let trackID = session.race.track.id
        guard let car = session.race.cars.first else { return }
        var improved = false
        if car.progress.lapTimes.count > notedLapCount {
            for lap in car.progress.lapTimes[notedLapCount...] {
                improved = hiscores.recordLap(lap, track: trackID) || improved
            }
            notedLapCount = car.progress.lapTimes.count
        }
        if !notedFinish, let finished = car.progress.finishedAt {
            notedFinish = true
            improved =
                hiscores.recordRace(
                    ticks: finished - session.race.config.countdownTicks,
                    recording: session.recording,
                    config: session.race.config,
                    track: trackID
                ) || improved
        }
        if improved {
            hiscoreFile.save(hiscores)
        }
    }

    /// Car colors in car order (humans first, then AI), for renderer + HUD.
    public var carColors: [Color] {
        let humanColors = rig?.players.map(\.colorIndex) ?? Array(colorIndices.prefix(playerCount))
        return (humanColors + aiColorIndices).map { Self.palette[$0] }
    }
}

/// The whole app: setup screen or the race.
public struct GameView: View {
    @StateObject private var game = CouchGame()

    public init() {}

    public var body: some View {
        ZStack {
            switch game.phase {
            case .setup:
                SetupView(game: game)
            case .racing:
                if let session = game.session, let rig = game.rig {
                    RaceScreen(game: game, session: session, rig: rig)
                }
            }
        }
        .statusBarHiddenIfAvailable()
        .persistentSystemOverlays(.hidden)
    }
}

extension View {
    func statusBarHiddenIfAvailable() -> some View {
        #if os(iOS)
        return statusBarHidden(true)
        #else
        return self
        #endif
    }

    func pillStyle() -> some View {
        font(.callout.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.35), in: Capsule())
            .foregroundStyle(.white)
    }
}
