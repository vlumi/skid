import SkidCore
import SwiftUI

@MainActor
public final class CouchGame: ObservableObject {
    public enum Phase {
        case setup
        case racing
        case editing
    }

    /// The track being built in the editor. A piece list, live-previewed and
    /// compiled on save. Nil until the editor is opened.
    ///
    /// This is also the **custom track slot**: one permanent place to build and
    /// race your own design. It persists across launches as a share code, so
    /// the track survives quitting the app — and the same code is what gets
    /// pasted into the repo to promote a design to a built-in.
    @Published public var editorLayout: TrackLayout? {
        didSet {
            saveCustomTrack()
            syncEditedTrackToLibrary()
        }
    }

    /// Placement verdicts memoised for the current piece list — see
    /// `editorCanAppend`. Not `@Published` on purpose: it's a cache, and
    /// invalidating views over it would defeat its point.
    var appendVerdicts: (pieces: [PieceID], byPiece: [VerdictKey: Bool]) = ([], [:])
    /// The same cache for the head end (`editorCanPrepend`). Kept separate
    /// because the two ends give different verdicts on the same piece.
    var prependVerdicts: (pieces: [PieceID], byPiece: [VerdictKey: Bool]) = ([], [:])

    /// Undo/redo history as encoded snapshots — see `EditorUndo`. `@Published`
    /// because the buttons' enabled state reads off them.
    @Published var undoStack: [String] = []
    @Published var redoStack: [String] = []

    /// What a map tap means. One tap used to mean two things — select an end or
    /// toggle a checkpoint — so a stray seam hit was a silent real edit.
    public enum EditorMode: Equatable, Sendable {
        case build
        case gate
    }

    @Published public var editorMode: EditorMode = .build {
        // Gate mode owns map taps, so a piece selection would be stale chrome
        // pointing at something you can no longer act on.
        didSet { if editorMode == .gate { selectionRaw = nil } }
    }

    /// The selected piece's index — see `EditorSelection`.
    @Published var selectionRaw: Int?
    /// Which end of an open chain the palette builds from. Remembered so the common
    /// case stays one tap.
    @Published public var editorBuildEnd: CouchGame.BuildEnd = .tail

    /// **Whether pieces laid from here on get a guard railing.** Sticky, like the
    /// build end: railing a bridge is a run of pieces, so asking once beats
    /// toggling each piece afterwards. Off by default, matching
    /// `TrackLayout.railed`.
    @Published public var editorRailNewPieces = false

    public enum Mode: CaseIterable {
        case race
        case timeTrial
    }

    static let palette: [Color] = TrackRenderer.carPalette

    @Published public private(set) var phase: Phase = .setup
    @Published public var mode: Mode = .race
    /// **The most cars a race can hold** — the grid's own limit, which the palette
    /// matches (asserted by `CarPaletteTests`). Named here so the setup screen and
    /// the AI cap cannot drift from the geometry.
    public static let maxCars = PieceCompiler.Grid.slots
    /// The most HUMAN players one device can seat: four control bands around one
    /// map is what `CouchRig` lays out and what fits a phone. Separate from
    /// `maxCars` on purpose — the rest of the field is AI, or (later) other devices.
    public static let maxLocalPlayers = 4

    @Published public var playerCount = 1 {
        didSet { aiCount = min(aiCount, Self.maxCars - playerCount) }
    }
    @Published public var aiCount = 0
    @Published public var aiDifficulty: AIDriver.Difficulty = .medium
    /// Default colour per seat, in palette order — which is separation order, so a
    /// 1–4 player game gets the four furthest-apart colours. Sized to the whole
    /// field rather than to four seats, since the AI fills the rest.
    @Published public private(set) var colorIndices = Array(0..<PieceCompiler.Grid.slots)
    /// Each human player's control scheme, chosen in setup (Casual/Pro). One
    /// entry per seat; only the first `playerCount` are used.
    @Published public var schemes: [ControlScheme] = [.casual, .casual, .casual, .casual]
    @Published public var carContact = true
    /// The chosen circuit (a `Track.id` from `TrackLibrary.all`).
    @Published public var trackID = TrackLibrary.builtins[0].id
    /// 2P seating: side-by-side vs face-to-face.
    @Published public var faceToFace = false
    /// 3P seating: which quadrant stays open.
    @Published public var openCorner: ZoneCorner = .topLeft

    @Published public private(set) var session: GameSession?
    public private(set) var rig: CouchRig?
    public private(set) var hiscores: HiscoreBook
    public let settings = GameSettings()

    private let hiscoreFile = HiscoreFile()
    private let libraryFile: TrackLibraryFile
    /// Your saved tracks. Written on every editor change, but not yet READ by
    /// anything — the custom slot is still authoritative until the picker moves
    /// over, so a migration that gets this wrong cannot lose the slot.
    @Published public internal(set) var library = TrackLibraryBook()
    /// Which library row the editor is currently updating, so an edit replaces
    /// it rather than piling up a row per keystroke.
    var editedEntryID: String?

    func saveLibrary() { libraryFile.save(library) }
    /// Where the author identity comes from. Injectable so tests can supply a
    /// key (or none) without a Keychain.
    let signingKeys: SigningKeyStore
    /// What the last pasted code claimed — computed on paste, never on render.
    @Published var pastedAttributionRaw: TrackAttribution = .unsigned
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

    /// `signingKeys` is injectable so tests can run without a Keychain, which
    /// they must: `swift test` is headless and unentitled.
    /// `signingKeys` and `libraryFilename` are injectable so tests can run
    /// without a Keychain and without sharing one library file across the run —
    /// both are process-wide state that leaks between test methods otherwise.
    public init(
        signingKeys: SigningKeyStore = KeychainSigningKeyStore(),
        libraryFilename: String = "tracks.json"
    ) {
        self.signingKeys = signingKeys
        self.libraryFile = TrackLibraryFile(filename: libraryFilename)
        hiscores = hiscoreFile.load()
        // The custom track slot survives quitting: restore it before anything
        // reads it. (Set the stored value, not the property — the property's
        // observer would just re-save what we only read.)
        editorLayout = Self.restoredCustomTrack()
        library = Self.migratedLibrary(libraryFile.load(), slot: Self.restoredCustomTrackCode())
        editedEntryID = Self.restoredCustomTrackCode().map { TrackCode.contentCode(of: $0) }
        libraryFile.save(library)
        // Push persisted render knobs (elevation feel) into their globals
        // before the first frame draws.
        settings.applyRenderTuning()
        // Dev affordance for automated screenshots/tests: launch straight
        // into a race (`-skid-players N -skid-autostart`).
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-skid-players"),
            index + 1 < arguments.count, let count = Int(arguments[index + 1])
        {
            playerCount = max(1, min(Self.maxLocalPlayers, count))
        }
        if let index = arguments.firstIndex(of: "-skid-ai"),
            index + 1 < arguments.count, let count = Int(arguments[index + 1])
        {
            aiCount = max(0, min(Self.maxCars - playerCount, count))
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
            clearUndoHistory()
        }
        editorMode = .build  // never open in a mode left on from last time
        // Open with the growing end selected, so the palette is live without a tap.
        // Building is a property of a SELECTED end now, so with nothing selected the
        // editor would greet the author with a greyed-out palette.
        editorSelect((editorLayout?.pieces.count ?? 1) - 1)
        sound.stop()
        phase = .editing
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

    /// The per-tick input tap: humans read their own control source, the rest
    /// come from the AI fleet.
    private func inputSource(humans: Int) -> (PlayerID, Race) -> CarInput {
        let fleet = aiFleet
        return { [weak rig] player, race in
            guard player.rawValue < humans else { return fleet.input(for: player, in: race) }
            guard let rig, rig.players.indices.contains(player.rawValue) else { return .coast }
            let controls = rig.players[player.rawValue]
            let source = controls.source(for: controls.scheme)
            // Heading-aware schemes (aim-to-drive) need where the car faces and
            // how fast it's going along that nose — SIGNED, so "already
            // reversing" is distinguishable from "driving forward fast".
            if let headingAware = source as? HeadingAwareControlSource,
                let car = race.cars.first(where: { $0.id == player })
            {
                headingAware.setCar(
                    heading: car.state.heading,
                    forwardSpeed: car.state.velocity.dot(car.state.forward),
                    speed: car.state.velocity.length)
            }
            return source.input(for: player, at: race.tick)
        }
    }

    private func makeSession(humans: Int, totalCars: Int) -> GameSession {
        let players = (0..<totalCars).map { PlayerID($0) }
        let track = selectedTrack()
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
        let session = GameSession(
            track: track, players: players, config: config, seed: seed,
            tuning: settings.carTuning, ghost: ghost,
            inputFor: inputSource(humans: humans))
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
            // Stored in degrees, used in radians.
            controls.casual.reverseThreshold = settings.aimForwardArcDegrees * .pi / 180
            controls.casual.fullSteerError = settings.aimTailSwingDegrees * .pi / 180
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
