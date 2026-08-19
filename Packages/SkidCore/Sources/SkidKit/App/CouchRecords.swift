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
        // **Who is driving.** Exactly one human by the guard above, so seat 0 is the
        // answer; a guest has no name and stores none.
        let holder = entrants.first?.profileID.flatMap { profiles.profile(id: $0)?.name }
        var improved = false
        if car.progress.lapTimes.count > notedLapCount {
            for lap in car.progress.lapTimes[notedLapCount...] {
                // **Read the standing record BEFORE the write**, which is the only moment
                // it is knowable: `recordLap` replaces it, so afterwards the book agrees
                // with the run and every lap would look like a record.
                let previous = hiscores.best(for: trackID).bestLapTicks
                if hiscores.recordLap(lap, track: trackID, holder: holder) {
                    improved = true
                    runRecords.lapRecord = RunRecords.Improvement(ticks: lap, previous: previous)
                }
            }
            notedLapCount = car.progress.lapTimes.count
        }
        if !notedFinish, let finished = car.progress.finishedAt {
            notedFinish = true
            let previousRace = hiscores.best(for: trackID).raceTicks
            let raceTicks = finished - session.race.config.countdownTicks
            // Cut the ghost ONLY when this run can actually take the record —
            // it used to be cut on every finish, before recordRace decided.
            if raceTicks < (previousRace ?? .max) {
                let setRace = hiscores.recordRace(
                    ticks: raceTicks,
                    // Cut here, where the finished race still knows where its laps
                    // fell — from the poses captured during the run, so this is a
                    // slice, not a replay (the replay was the finish-line hitch).
                    ghost: session.recording.bestLapGhost(
                        on: session.race.track, lapTimes: car.progress.lapTimes,
                        config: session.race.config,
                        startPoses: session.lapStartPoses),
                    config: session.race.config,
                    track: trackID,
                    holder: holder
                )
                if setRace {
                    runRecords.raceRecord = RunRecords.Improvement(
                        ticks: raceTicks, previous: previousRace)
                }
                improved = setRace || improved
            }
        }
        if improved {
            hiscoreFile.save(hiscores)
        }
    }
}
