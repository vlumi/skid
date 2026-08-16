import SkidCore
import SwiftUI

/// **The race's audio frame, and the countdown's beeps.**
///
/// Split out of `CouchGame` on the file-length limit, and it is a coherent subject: what
/// the race sounds like, as opposed to what it scores (`CouchRecords`) or where it goes
/// next (`CouchNavigation`).
extension CouchGame {
    public func audioFrame() {
        guard let session else { return }
        guard settings.soundOn, phase == .racing else {
            sound.stop()
            notedCountdownSeconds = nil
            return
        }
        sound.start()
        noteCountdownBeep(in: session.race)
        if session.paused || session.race.phase == .finished {
            sound.update(race: session.race, humanCount: humanCount, paused: true)
        }
    }

    /// **The countdown's beeps**, fired on the frame the clock crosses each second.
    ///
    /// Compares against the last value SEEN rather than recomputing from the tick, so a
    /// beep sounds exactly once per boundary however many frames render inside a second
    /// — and a paused or restarted race cannot replay one it already played.
    func noteCountdownBeep(in race: Race) {
        let now = StartBeeps.secondsRemaining(in: race)
        defer { notedCountdownSeconds = now }
        guard let previous = notedCountdownSeconds else { return }
        if let isFinal = StartBeeps.beep(secondsBefore: previous, secondsAfter: now) {
            sound.startBeep(final: isFinal)
        }
    }

}
