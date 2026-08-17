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
        // **Not until the ready gate clears.** The sim sits frozen at tick 0 in
        // `.countdown` while `!started` — three seconds showing, nothing moving — so the
        // "countdown begins" beep fired the instant the race screen appeared, before
        // anyone pressed Play. Reported from device. `RaceHUD` already gates the lights
        // on exactly this; the audio was the half that did not.
        if session.started {
            noteCountdownBeep(in: session.race)
        } else {
            // Cleared, so pressing Play still counts nil → 3 as the opening beep
            // rather than "no change" — the lights appear on that frame too.
            notedCountdownSeconds = nil
        }
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
        // **No early return on the first frame.** `notedCountdownSeconds` is nil exactly
        // when the countdown begins, which is when the first lights appear — bailing out
        // there is what left the opening state silent.
        let previous = notedCountdownSeconds
        defer { notedCountdownSeconds = now }
        if let isFinal = StartBeeps.beep(secondsBefore: previous, secondsAfter: now) {
            sound.startBeep(final: isFinal)
        }
    }

}
