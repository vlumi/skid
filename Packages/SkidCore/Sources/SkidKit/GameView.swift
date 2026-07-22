import SkidCore
import SwiftUI

/// Top-level couch-game state: setup → race → (results) → race again.
@MainActor
public final class CouchGame: ObservableObject {
    public enum Phase {
        case setup
        case racing
    }

    static let palette: [Color] = TrackRenderer.carPalette

    @Published public private(set) var phase: Phase = .setup
    @Published public var playerCount = 1
    @Published public private(set) var colorIndices = [0, 1, 2, 3]
    @Published public var carContact = true

    @Published public private(set) var session: GameSession?
    public private(set) var rig: CouchRig?

    private var seed: UInt64 = 1

    public init() {
        // Dev affordance for automated screenshots/tests: launch straight
        // into a race (`-skid-players N -skid-autostart`).
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-skid-players"),
            index + 1 < arguments.count, let count = Int(arguments[index + 1])
        {
            playerCount = max(1, min(4, count))
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
        let colors = Array(colorIndices.prefix(playerCount))
        let rig = CouchRig(colorIndices: colors, scheme: rig?.scheme ?? .dpad)
        self.rig = rig
        seed += 1
        session = Self.makeSession(
            rig: rig, playerCount: playerCount, carContact: carContact, seed: seed)
        phase = .racing
    }

    public func raceAgain() {
        guard let rig else { return }
        for player in rig.players {
            player.releaseAll()
        }
        seed += 1
        session = Self.makeSession(
            rig: rig, playerCount: playerCount, carContact: carContact, seed: seed)
    }

    public func backToSetup() {
        phase = .setup
        session = nil
        rig = nil
    }

    private static func makeSession(
        rig: CouchRig, playerCount: Int, carContact: Bool, seed: UInt64
    ) -> GameSession {
        let players = (0..<playerCount).map { PlayerID($0) }
        let config = RaceConfig(
            laps: 3, countdownTicks: 3 * Race.tickRate, carContact: carContact)
        let inputFor: (PlayerID, Tick) -> CarInput = { [weak rig] player, tick in
            guard let rig, rig.players.indices.contains(player.rawValue) else { return .coast }
            let controls = rig.players[player.rawValue]
            return controls.source(for: rig.scheme).input(for: player, at: tick)
        }
        return GameSession(players: players, config: config, seed: seed, inputFor: inputFor)
    }

    /// Car colors in car order, for the renderer and HUD.
    public var carColors: [Color] {
        (rig?.players.map(\.colorIndex) ?? Array(colorIndices.prefix(playerCount)))
            .map { Self.palette[$0] }
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
