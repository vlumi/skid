import Testing

@testable import SkidCore
@testable import SkidKit

/// **What a time trial shows of its own history.**
///
/// The point of these is the sliding window: a trial laps until you stop, so the list has
/// to drop old laps while keeping their real lap numbers and never losing sight of the best.
struct LapHistoryTests {
    /// Nothing driven yet, nothing listed — and no best to pin.
    @Test func aRunWithNoLapsShowsNothing() {
        let history = LapHistory(lapTimes: [], limit: 5)
        #expect(history.rows.isEmpty)
        #expect(history.pinnedBest == nil)
    }

    /// **Every lap is listed while they fit, and the best is starred in place.**
    @Test func shortRunsListEveryLapAndStarTheBest() {
        let history = LapHistory(lapTimes: [620, 580, 610], limit: 5)
        #expect(history.rows.map(\.number) == [1, 2, 3])
        #expect(history.rows.map(\.ticks) == [620, 580, 610])
        #expect(history.rows.map(\.isBest) == [false, true, false])
        // The best is on screen, so there is nothing to pin below.
        #expect(history.pinnedBest == nil)
    }

    /// **Lap numbers are the real ones**, not positions in the window.
    ///
    /// The trap `suffix` avoids: re-enumerating the window would label a 9th lap "Lap 4".
    @Test func theWindowKeepsTrueLapNumbers() {
        let history = LapHistory(lapTimes: [700, 690, 680, 670, 660, 650, 640], limit: 3)
        #expect(history.rows.map(\.number) == [5, 6, 7])
        #expect(history.rows.map(\.ticks) == [660, 650, 640])
    }

    /// **A best that has scrolled away gets pinned**, so the target stays visible.
    @Test func aBestOutsideTheWindowIsPinned() {
        // Lap 1 is the best, and a 3-lap window shows laps 3-5.
        let history = LapHistory(lapTimes: [500, 700, 690, 680, 670], limit: 3)
        #expect(history.rows.map(\.number) == [3, 4, 5])
        #expect(history.rows.allSatisfy { !$0.isBest })
        #expect(history.pinnedBest == 500)
    }

    /// A best still inside the window is starred there rather than pinned twice.
    @Test func aBestInsideTheWindowIsNotPinned() {
        let history = LapHistory(lapTimes: [700, 690, 500, 680, 670], limit: 3)
        #expect(history.rows.map(\.isBest) == [true, false, false])
        #expect(history.pinnedBest == nil)
    }

    /// **Exactly one lap is ever starred**, even when several share the fastest time.
    ///
    /// Not a hypothetical: a real 8-lap AI run turned in `[711, 622, 623, 622, 622, ...]`
    /// and starring "every lap equal to the best" lit up three rows, which says nothing.
    /// The star belongs to the lap that SET the time.
    @Test func onlyTheLapThatSetTheBestIsStarred() {
        let history = LapHistory(lapTimes: [711, 622, 623, 622, 622], limit: 5)
        #expect(history.rows.filter(\.isBest).map(\.number) == [2])
    }

    /// A tie does not steal the star from the lap that set it — so once that lap scrolls
    /// away the best is pinned, rather than the column silently losing its star.
    @Test func aLaterTieDoesNotHideThePin() {
        let history = LapHistory(lapTimes: [500, 700, 690, 500], limit: 3)
        #expect(history.rows.filter(\.isBest).isEmpty)
        #expect(history.pinnedBest == 500)
    }

    /// A nonsense limit lists nothing rather than trapping, and still pins the best so the
    /// run's number survives.
    @Test func aNonPositiveLimitListsNothing() {
        let history = LapHistory(lapTimes: [600, 580], limit: 0)
        #expect(history.rows.isEmpty)
        #expect(history.pinnedBest == 580)
    }
}
