import SkidCore
import SwiftUI

/// **Recording what happened: personal bests.**
///
/// Split out of `CouchGame` on the file-length limit. A coherent subject, and about to
/// grow: records are keyed by track today, and making them per-profile is the next
/// step now that `SeatIdentity` exists.
extension CouchGame {
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
                    // Cut here, where the finished race still knows where its laps fell.
                    ghost: session.recording.bestLapGhost(
                        on: session.race.track, lapTimes: car.progress.lapTimes,
                        config: session.race.config),
                    config: session.race.config,
                    track: trackID
                ) || improved
        }
        if improved {
            hiscoreFile.save(hiscores)
        }
    }
}
