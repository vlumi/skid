import SkidCore
import SwiftUI

@MainActor
public final class CouchGame: ObservableObject {
    public enum Phase: Equatable {
        /// **The front door**: solo, couch, nearby, or the editor.
        ///
        /// Added ahead of `setup` rather than replacing it. The old flat screen was
        /// doing two jobs — choosing who you play with, and configuring the race —
        /// and only the second one belongs to a mode. See `HomeView`.
        case menu
        case setup
        case racing
        case editing
        /// Host/join lobby for a networked race.
        case networking
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

    @Published public internal(set) var phase: Phase = .menu
    @Published public var mode: Mode = .race
    /// **What a race is allowed to hold today: four cars.**
    ///
    /// A **soft cap**, not a limit of the game. The grid seats nine
    /// (`PieceCompiler.Grid.slots`), the palette carries nine measured colors, and
    /// nine race correctly — that support is built, tested and staying. What is not
    /// yet known is how nine behave on a real phone, and finding out belongs in the
    /// device optimisation pass rather than now.
    ///
    /// Four is also enough on its own terms: four players on one screen is already
    /// hectic, and a race is short enough that people rotate.
    ///
    /// **Raising it is this one number.** Everything downstream reads it — the setup
    /// screen's ranges, both seat clamps, the AI fleet — so the day the device numbers
    /// exist, `maxCars = fieldCapacity` is the whole change.
    public static let maxCars = 4

    /// What the grid and palette could seat if `maxCars` were lifted — kept named so
    /// the soft cap reads as a deliberate ceiling rather than the engine's limit, and
    /// so a test can assert the two have not drifted apart.
    public static let fieldCapacity = PieceCompiler.Grid.slots

    /// The most HUMAN players one device can seat: four control bands around one
    /// map is what `CouchRig` lays out and what fits a phone. Separate from
    /// `maxCars` on purpose — the rest of the field is AI, or (later) other devices.
    ///
    /// Reads from `RaceRoster`, which is where the same number is a *protocol*
    /// limit: a joining device announces how many seats it brings and the host
    /// validates that claim. Two independent 4s could drift, and a peer whose UI
    /// offered a seat the protocol refused would fail to join for no visible reason.
    public static let maxLocalPlayers = RaceRoster.maxSeatsPerDevice

    /// **Both counts clamp themselves**, so no caller can ask for a field the grid
    /// cannot hold.
    ///
    /// This used to be enforced by whoever happened to be setting them — the setup
    /// screen offered a valid range, the CLI parser clamped, and `startRace` clamped
    /// again with its own literal. Three places, and the one that mattered was wrong:
    /// a solo player's field was silently cut to three AI while the grid showed nine
    /// slots. Clamping at the property makes the invariant impossible to route around.
    /// **Fill the empty grid with AI, or race whoever is here alone.**
    ///
    /// A toggle rather than a count: "how many opponents?" is a question nobody has a
    /// basis to answer before driving, and a third number could disagree with the list
    /// and the grid. On by default, because one person plus an empty track is a time
    /// trial rather than a race.
    ///
    /// Local only — a nearby field is built by whoever hosts it, and the protocol has no
    /// AI seat at all. `aiCount` enforces that rather than this flag being reset.
    @Published public var fillWithAI = true

    /// How well the AI drives.
    @Published public var aiDifficulty: AIDriver.Difficulty = .medium
    /// Default color per seat, in palette order — which is separation order, so a
    /// 1–4 player game gets the four furthest-apart colors. Sized to the whole
    /// field rather than to four seats, since the AI fills the rest.
    @Published public private(set) var colorIndices = Array(0..<PieceCompiler.Grid.slots)
    /// Each human player's control scheme, chosen in setup (Casual/Pro). One
    /// entry per seat; only the first `playerCount` are used.
    @Published public var schemes: [ControlScheme] = [.casual, .casual, .casual, .casual]
    @Published public var carContact = true
    /// The chosen circuit (a `Track.id` from `TrackLibrary.all`).
    @Published public var trackID = TrackLibrary.builtins[0].id
    /// 2P seating: face-to-face (default) vs side-by-side.
    ///
    /// Face-to-face is what two people do with a phone flat on a table — full-width
    /// band each. Side-by-side halves that and is cramped on an iPhone; it exists
    /// because cramming 3–4 players onto one screen needs it, not because two
    /// players want it. Eventually a per-device choice, once devices differ.
    @Published public var faceToFace = true
    /// 3P seating: which quadrant stays open.
    @Published public var openCorner: ZoneCorner = .topLeft

    @Published public internal(set) var session: GameSession?
    public internal(set) var rig: CouchRig?
    public internal(set) var hiscores: HiscoreBook
    public let settings = GameSettings()

    let hiscoreFile = HiscoreFile()
    let profileFile: ProfileFile
    private let libraryFile: TrackLibraryFile

    /// **Everyone with a name on this device.** Empty is the normal starting state:
    /// guests need no profile, so the app is fully usable before this holds anything.
    @Published public internal(set) var profiles = ProfileBook()

    /// **Who is in each seat**, parallel to the seats themselves.
    ///
    /// Sized to `maxLocalPlayers` and defaulting to guests, so a seat always has an
    /// answer and no lookup can fail. A player who never opens the profile picker
    /// races as a guest forever, which is the intended default rather than a fallback.
    @Published public internal(set) var seatIdentities: [SeatIdentity] =
        Array(repeating: .guest, count: CouchGame.maxLocalPlayers)

    /// **The field as one list** — every car, and who drives it.
    ///
    /// The single source of truth for how many humans and how many AI are racing: both
    /// counts are *derived* from it. They used to be independent steppers that had to
    /// agree with each other and with the grid, and three numbers meant three chances to
    /// disagree — which they once did, silently cutting a solo field to three AI.
    ///
    /// Starts as one guest, because the app opens for somebody who wants to drive, and
    /// one row is a legitimate race: solo against the AI.
    @Published public internal(set) var entrants: [RaceEntrant] = [.guest]

    /// **Which profile each row last held**, so the three-way toggle is sticky: switch a
    /// row to AI and back and the same person returns rather than being asked again.
    /// Session-only — who is sitting where is not a property of the device.
    var rememberedProfiles: [Int: UUID] = [:]
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
    let aiFleet = AIFleet()
    let sound = SoundEngine()
    let haptics = Haptics()
    var aiColorIndices: [Int] = []
    /// Race seed, bumped before every race and recorded with each replay so
    /// runs stay reproducible. Seeded from the clock ONCE at launch (view
    /// layer only — the sim itself never touches wall-clock time) so grids
    /// differ across app runs instead of repeating from 1 each session.
    private var seed: UInt64 = UInt64(Date().timeIntervalSince1970.bitPattern)
    var notedLapCount = 0
    var notedFinish = false

    /// `signingKeys` is injectable so tests can run without a Keychain, which
    /// they must: `swift test` is headless and unentitled.
    /// `signingKeys` and `libraryFilename` are injectable so tests can run
    /// without a Keychain and without sharing one library file across the run —
    /// both are process-wide state that leaks between test methods otherwise.
    public init(
        signingKeys: SigningKeyStore = KeychainSigningKeyStore(),
        libraryFilename: String = "tracks.json",
        profileFilename: String = "profiles.json"
    ) {
        self.signingKeys = signingKeys
        self.libraryFile = TrackLibraryFile(filename: libraryFilename)
        self.profileFile = ProfileFile(filename: profileFilename)
        hiscores = hiscoreFile.load()
        profiles = profileFile.load()
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
            // Kept for the screenshot/test launch arguments: any positive count means
            // "fill the grid", which is the only AI choice there is now.
            fillWithAI = count > 0
        }
        if let index = arguments.firstIndex(of: "-skid-track"), index + 1 < arguments.count {
            trackID = TrackLibrary.track(id: arguments[index + 1]).id
        }
        // Straight to the race options, skipping the front door — for screenshots of
        // the setup screen, which is otherwise two taps in and unreachable from a
        // launch argument.
        if arguments.contains("-skid-setup") {
            phase = .setup
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
        // Recency, so this phone's regulars sort to the top of the picker. Guests are
        // skipped — there is nothing to note against them.
        markSeatedProfilesPlayed()
        let humans = mode == .timeTrial ? 1 : playerCount
        // Clamped against the FIELD, not the four local seats. This read
        // `4 - humans` and silently dropped a solo player's field to three AI —
        // the grid showed nine slots and only four cars turned up, reported from
        // device. Two other clamps were named; this one was missed.
        let ai = mode == .timeTrial ? 0 : min(aiCount, Self.maxCars - humans)
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
}
