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
        case editing
    }

    /// The track being built in the editor. A piece list, live-previewed and
    /// compiled on save. Nil until the editor is opened.
    @Published public var editorLayout: TrackLayout?

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
    /// Each human player's control scheme, chosen in setup (Casual/Pro). One
    /// entry per seat; only the first `playerCount` are used.
    @Published public var schemes: [ControlScheme] = [.casual, .casual, .casual, .casual]
    @Published public var carContact = true
    /// The chosen circuit (a `Track.id` from `TrackLibrary.all`).
    @Published public var trackID = "practice-loop"
    /// 2P seating: side-by-side vs face-to-face.
    @Published public var faceToFace = false
    /// 3P seating: which quadrant stays open.
    @Published public var openCorner: ZoneCorner = .topLeft

    @Published public private(set) var session: GameSession?
    public private(set) var rig: CouchRig?
    public private(set) var hiscores: HiscoreBook
    public let settings = GameSettings()

    private let hiscoreFile = HiscoreFile()
    private let aiFleet = AIFleet()
    private let sound = SoundEngine()
    private let haptics = Haptics()
    private var aiColorIndices: [Int] = []
    /// Race seed, bumped before every race and recorded with each replay so
    /// runs stay reproducible. Seeded from the clock ONCE at launch (view
    /// layer only — the sim itself never touches wall-clock time) so grids
    /// differ across app runs instead of repeating from 1 each session.
    private var seed: UInt64 = UInt64(Date().timeIntervalSince1970.bitPattern)
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
        if let index = arguments.firstIndex(of: "-skid-track"), index + 1 < arguments.count {
            trackID = TrackLibrary.track(id: arguments[index + 1]).id
        }
        if arguments.contains("-skid-autostart") {
            startRace()
            // Screenshots/tests want a running race, not the ready gate.
            session?.started = true
        }
    }

    /// Toggle one player's control scheme (Casual ↔ Pro).
    public func toggleScheme(slot: Int) {
        guard schemes.indices.contains(slot) else { return }
        schemes[slot] = schemes[slot] == .casual ? .pro : .casual
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
            colorIndices: humanColors, schemes: Array(schemes.prefix(humans)), seating: seating)
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
        sound.stop()
    }

    /// Open the track editor. A new track starts with just the start-grid
    /// piece — you build outward from its loose end.
    public func openEditor() {
        if editorLayout == nil {
            editorLayout = TrackLayout(
                pieces: [PieceCatalog.startPieceID], gateSeams: [0])
        }
        sound.stop()
        phase = .editing
    }

    /// Append a catalog piece to the end of the layout (extends the loose end).
    public func editorAppend(_ id: PieceID) {
        editorLayout?.pieces.append(id)
    }

    /// Append the context-aware ramp: up (id 13) from the ground, down (id 14)
    /// from the deck — with only two elevations the one button does both.
    public func editorRamp() {
        guard let layout = editorLayout, let last = layout.walk().placed.last else {
            editorAppend(13)
            return
        }
        // On the deck (height up) → ramp down; on the ground → ramp up.
        editorAppend(last.exitHeight > 0.5 ? 14 : 13)
    }

    /// Remove the last piece (never the start piece — a track must keep one).
    public func editorDeleteLast() {
        guard var layout = editorLayout, layout.pieces.count > 1 else { return }
        layout.pieces.removeLast()
        // Drop any gate seam that no longer has a piece.
        layout.gateSeams = layout.gateSeams.filter { $0 < layout.pieces.count }
        editorLayout = layout
    }

    /// Start a fresh track (just the start piece).
    public func editorReset() {
        editorLayout = TrackLayout(pieces: [PieceCatalog.startPieceID], gateSeams: [0])
    }

    /// Whether the current layout is saveable (closed + valid).
    public func editorIsSaveable() -> Bool {
        guard let editorLayout else { return false }
        return TrackValidator.validate(editorLayout).isSaveable
    }

    /// Compile the current editor layout to a runtime `Track` for preview.
    /// Nil if it isn't saveable yet. (Test-driving it in a real race arrives
    /// with step 3 — wiring editor tracks into the game.)
    public func editorTrack() -> Track? {
        guard let editorLayout else { return nil }
        return try? PieceCompiler.compile(editorLayout, id: "editor-preview")
    }

    /// Called every frame by the race screen: audio lifecycle follows the
    /// toggles, and a paused race falls silent instead of droning.
    public func audioFrame() {
        guard let session else { return }
        guard settings.soundOn, phase == .racing else {
            sound.stop()
            return
        }
        sound.start()
        if session.paused || session.race.phase == .finished {
            sound.update(race: session.race, humanCount: humanCount, paused: true)
        }
    }

    private var humanCount: Int { rig?.players.count ?? 1 }

    private func makeSession(humans: Int, totalCars: Int) -> GameSession {
        let players = (0..<totalCars).map { PlayerID($0) }
        let track = TrackLibrary.track(id: trackID)
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
            ? GhostPlayback(record: hiscores.best(for: track.id), track: track)
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
                let source = controls.source(for: controls.scheme)
                // Heading-aware schemes (aim-to-drive) need where the car
                // faces and how fast it's going (flip vs. reverse).
                if let headingAware = source as? HeadingAwareControlSource,
                    let car = race.cars.first(where: { $0.id == player })
                {
                    headingAware.setCar(
                        heading: car.state.heading, speed: car.state.velocity.length)
                }
                return source.input(for: player, at: race.tick)
            }
            return fleet.input(for: player, in: race)
        }
        let session = GameSession(
            track: track, players: players, config: config, seed: seed,
            tuning: settings.carTuning, ghost: ghost,
            inputFor: inputFor)
        session.onTick = { [weak self] race in
            guard let self else { return }
            if self.settings.soundOn {
                self.sound.update(race: race, humanCount: humans, paused: false)
            }
            if self.settings.hapticsOn {
                self.haptics.play(events: race.lastEvents, humanCount: humans)
            }
        }
        return session
    }

    /// Push the persisted control tuning onto every player's schemes —
    /// called each frame, so panel changes apply live mid-race.
    public func applyControlTuning() {
        guard let rig else { return }
        for controls in rig.players {
            controls.pro.deadzone = settings.dpadDeadzone
            controls.pro.radius = settings.dpadTravel
            controls.pro.levels = settings.dpadSteps > 0 ? settings.dpadSteps : nil
            controls.pro.expo = settings.dpadExpo
            controls.casual.reverseBelowSpeed = settings.aimReverseBelowSpeed
            controls.casual.throttleEase = settings.aimThrottleEase
        }
    }

    /// Called every frame by the race screen: fold the (single) human's
    /// results into the hiscores as they happen. Multi-human races don't
    /// record — hiscores are personal. Slowed-pace or dialed-physics runs
    /// never record: bests are set on the stock machine only (recordings
    /// replay with stock tuning, so anything else would lie).
    public func noteProgress() {
        guard let session, let rig, rig.players.count == 1, settings.pace > 0.999,
            settings.isStockPhysics
        else {
            return
        }
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
            case .editing:
                EditorView(game: game)
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

    /// Thumbs live at the screen edges during play: make system edge swipes
    /// (home indicator, notification/control center) require the deliberate
    /// double-swipe — but only while actually racing. Menus, pause, and
    /// results keep normal one-swipe system gestures.
    func defersEdgeSwipes(_ active: Bool) -> some View {
        #if os(iOS)
        return defersSystemGestures(on: active ? .all : [])
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
