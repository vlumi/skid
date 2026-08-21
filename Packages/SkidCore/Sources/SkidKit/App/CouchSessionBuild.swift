import SkidCore
import SwiftUI

/// **Building the race a mode asks for** — the input tap and the session.
///
/// Split out of `CouchGame` on the file-length limit, and a coherent seam: this
/// is the one place that turns "which mode, how many cars" into a live
/// `GameSession`, so a new mode's rules (laps, ghost, countdown) are added here
/// and nowhere else.
extension CouchGame {
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

    func makeSession(humans: Int, totalCars: Int) -> GameSession {
        let players = (0..<totalCars).map { PlayerID($0) }
        let track = selectedTrack()
        let config: RaceConfig
        switch mode {
        // A tournament race IS a lap race — the series only changes what happens
        // between races, never how one is driven.
        case .race, .tournament:
            config = RaceConfig(
                laps: 3, countdownTicks: 3 * Race.tickRate)
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
        notedCountdownSeconds = nil
        runRecords = .none
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

}
