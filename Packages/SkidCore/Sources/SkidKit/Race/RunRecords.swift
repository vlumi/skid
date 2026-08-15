import SkidCore

/// **What this run did to the track's records**, kept so the screen can say so.
///
/// `noteProgress` folds a run into the hiscore book as it happens, and the book only ever
/// holds the *current* best. So by the time anything draws, "is my best lap the record?"
/// is always yes — the write already happened. The answer has to be captured at write
/// time, which is what this is.
///
/// The two records are deliberately asymmetric, because the modes are:
///
/// - **A lap record can fall mid-run**, in a race or a trial alike (one lap record per
///   track — a fast lap is a fast lap, whichever mode drove it). A trial has no ending, so
///   this is the only thing it can ever report.
/// - **A race record needs a finish**, so it exists only where there is a results screen
///   to read it on.
public struct RunRecords: Equatable {
    /// This run set the track's best lap, and the time it beat (nil when there was no
    /// previous record — the first lap on a track is a record with nothing behind it).
    public var lapRecord: Improvement?
    /// This run set the track's best race. Races only; a trial never finishes.
    public var raceRecord: Improvement?

    /// A record that fell: what it is now, and what it was.
    public struct Improvement: Equatable {
        public init(ticks: Tick, previous: Tick?) {
            self.ticks = ticks
            self.previous = previous
        }

        public var ticks: Tick
        /// The time this beat. Nil when nothing was there before.
        public var previous: Tick?
    }

    /// Nothing recorded yet — also what a run that does not qualify keeps forever.
    public static let none = RunRecords()

    public init() {}

    public var isEmpty: Bool { lapRecord == nil && raceRecord == nil }
}
