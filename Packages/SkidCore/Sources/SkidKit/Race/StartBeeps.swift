import SkidCore

/// **When the countdown beeps, and which beep it is.**
///
/// The lights are the countdown; this is the half you hear while looking at the track
/// rather than at the gantry. Three counting blips, then a higher, louder one on go —
/// so the moment you are waiting for sounds *unlike* the three before it, instead of
/// being a fourth identical tone you have to count.
///
/// Split out of the frame callback because "did this frame cross a second boundary?" is
/// arithmetic, and the answer has to be exactly once per boundary: the audio frame runs
/// at display rate, so a naive "is the clock near a second?" fires the same beep on
/// every frame it is near one.
enum StartBeeps {
    /// The beep to play, given the countdown's whole seconds remaining before and after
    /// this frame's tick. Nil on most frames — a beep lands only where the lights change.
    ///
    /// **One beep per light state, including the first.** `secondsBefore` is nil on the
    /// frame the countdown begins, and treating that as "no change" left the opening
    /// state silent: three light states, two beeps, and a countdown you could watch and
    /// hear disagree. The lights and the beeps are the same countdown, so they change
    /// together.
    ///
    /// - Returns: `true` for the final (lights-out) beep, `false` for a counting one.
    static func beep(secondsBefore: Int?, secondsAfter: Int?) -> Bool? {
        // The countdown beginning: the first lights appear, so the first beep sounds.
        if secondsBefore == nil, let after = secondsAfter, after > 0 {
            return false
        }
        // Counting down: 3→2, 2→1 are counting beeps.
        if let before = secondsBefore, let after = secondsAfter, after < before, after > 0 {
            return false
        }
        // The start itself: the countdown ended this frame. Either it stepped to zero,
        // or the phase left the countdown entirely — both are the same event, and both
        // must produce exactly one beep.
        if let before = secondsBefore, before > 0, (secondsAfter ?? 0) <= 0 {
            return true
        }
        return nil
    }

    /// Whole seconds left in a race's countdown, or nil once it is running.
    ///
    /// Rounded UP, matching the gantry: with 1.5s left the lights show "2", so the beep
    /// that fires when this drops to 1 is the one the player sees land.
    static func secondsRemaining(in race: Race) -> Int? {
        guard case .countdown(let remaining) = race.phase else { return nil }
        return (remaining + Race.tickRate - 1) / Race.tickRate
    }
}
