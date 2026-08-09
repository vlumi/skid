import XCTest

@testable import SkidCore

/// The spike's core measurement: two peers trading state hashes, and the first
/// tick they disagree on. A divergence found here is the *point* of the
/// experiment, so the watch is judged on how clearly it reports one.
final class DivergenceWatchTests: XCTestCase {
    func testAgreementIsUnknownUntilSomebodyReports() {
        // Nil, not true. "Nobody disagreed" and "everybody agreed" are different
        // claims, and conflating them lets a silent peer read as a healthy one —
        // which on a spike would be reported as a success.
        var watch = DivergenceWatch()
        watch.record(tick: 0, hash: 111)
        XCTAssertNil(watch.agreement(at: 0), "a silent peer read as agreement")
        watch.received(tick: 0, hash: 111, from: "b")
        XCTAssertEqual(watch.agreement(at: 0), true)
    }

    func testAgreementIsUnknownForATickWeHaveNotSimulated() {
        var watch = DivergenceWatch()
        watch.received(tick: 9, hash: 1, from: "b")
        XCTAssertNil(watch.agreement(at: 9))
    }

    func testADisagreementIsReportedWithItsTick() {
        var watch = DivergenceWatch()
        for tick in 0..<10 { watch.record(tick: tick, hash: UInt64(tick)) }
        for tick in 0..<10 { watch.received(tick: tick, hash: UInt64(tick), from: "b") }
        XCTAssertNil(watch.firstDivergence)

        watch.record(tick: 10, hash: 999)
        watch.received(tick: 10, hash: 1000, from: "b")
        XCTAssertEqual(watch.firstDivergence?.tick, 10)
        XCTAssertEqual(watch.firstDivergence?.peer, "b")
        XCTAssertEqual(watch.firstDivergence?.mine, 999)
        XCTAssertEqual(watch.firstDivergence?.theirs, 1000)
        XCTAssertEqual(watch.agreement(at: 10), false)
    }

    func testItDoesNotMatterWhichSideArrivesFirst() {
        // A peer's report routinely lands before our own tick is simulated (it may
        // be ahead of us), so comparison cannot depend on ordering.
        var theirsFirst = DivergenceWatch()
        theirsFirst.received(tick: 3, hash: 7, from: "b")
        theirsFirst.record(tick: 3, hash: 8)
        XCTAssertEqual(theirsFirst.firstDivergence?.tick, 3)

        var mineFirst = DivergenceWatch()
        mineFirst.record(tick: 3, hash: 8)
        mineFirst.received(tick: 3, hash: 7, from: "b")
        XCTAssertEqual(mineFirst.firstDivergence?.tick, 3)
    }

    func testTheEarliestDivergenceWinsEvenWhenReportedLate() {
        // Reports arrive out of order, so the first one SEEN is not necessarily
        // the first one that happened — and the earliest tick is the useful
        // diagnosis. Keeping first-seen would blame whichever packet landed first.
        var watch = DivergenceWatch()
        for tick in 0..<100 { watch.record(tick: tick, hash: UInt64(tick)) }
        watch.received(tick: 90, hash: 9999, from: "b")
        XCTAssertEqual(watch.firstDivergence?.tick, 90)
        watch.received(tick: 40, hash: 8888, from: "b")
        XCTAssertEqual(watch.firstDivergence?.tick, 40, "a later report of an earlier tick lost")
        // And a still-later report of a LATER tick must not displace it.
        watch.received(tick: 95, hash: 7777, from: "b")
        XCTAssertEqual(watch.firstDivergence?.tick, 40)
    }

    func testOnePeerDivergingDoesNotImplicateTheOthers() {
        // Three peers, one wrong: the report must name the one that disagrees, and
        // the healthy peer must still read as agreeing.
        var watch = DivergenceWatch()
        watch.record(tick: 5, hash: 42)
        watch.received(tick: 5, hash: 42, from: "good")
        watch.received(tick: 5, hash: 43, from: "bad")
        XCTAssertEqual(watch.firstDivergence?.peer, "bad")
        XCTAssertEqual(watch.agreeingPeers, ["good"])
    }

    func testAPeerRunningAheadOfUsIsNotYetAgreeing() {
        // A peer ahead of us has reported ticks we have not simulated, so there is
        // nothing to compare — it must not count as agreeing. Reachable in normal
        // play (any peer with a shorter input path runs ahead), and the branch
        // Codecov flagged as unreached in #149.
        var watch = DivergenceWatch()
        watch.record(tick: 5, hash: 42)
        watch.received(tick: 99, hash: 42, from: "ahead")
        XCTAssertEqual(watch.agreeingPeers, [], "a peer with no shared tick counted as agreeing")
        XCTAssertNil(watch.agreement(at: 99), "we cannot vouch for a tick we have not run")
        // Once it reports a tick we HAVE run, it counts.
        watch.received(tick: 5, hash: 42, from: "ahead")
        XCTAssertEqual(watch.agreeingPeers, ["ahead"])
    }

    func testAgreementNeedsEveryReporterNotJustOne() {
        // `agreement(at:)` is a claim about all reports for that tick. One matching
        // peer must not vouch for a disagreeing one.
        var watch = DivergenceWatch()
        watch.record(tick: 1, hash: 5)
        watch.received(tick: 1, hash: 5, from: "a")
        XCTAssertEqual(watch.agreement(at: 1), true)
        watch.received(tick: 1, hash: 6, from: "b")
        XCTAssertEqual(watch.agreement(at: 1), false, "a matching peer vouched for a bad one")
    }

    func testTheWindowIsBoundedSoALongRaceDoesNotGrowForever() {
        // A hash per tick at 60 Hz for a five-minute race is 18 000 entries per
        // peer. The window keeps two seconds, which is ample for a late report.
        var watch = DivergenceWatch()
        for tick in 0..<(DivergenceWatch.window * 3) {
            watch.record(tick: tick, hash: UInt64(tick))
            watch.received(tick: tick, hash: UInt64(tick), from: "b")
        }
        let old = 0
        XCTAssertNil(watch.agreement(at: old), "the window is not pruning old ticks")
        let recent = DivergenceWatch.window * 3 - 1
        XCTAssertEqual(watch.agreement(at: recent), true, "the window pruned a live tick")
    }

    func testTwoRacesThatReallyDivergeAreCaughtAtTheirFirstDifference() {
        // End to end against the real sim rather than invented numbers: two races
        // fed the same inputs until one is nudged, traded through the watch as two
        // peers would.
        let track = TrackLibrary.testRing()
        let seats = [PlayerID(0), PlayerID(1)]
        var peerA = Race(track: track, players: seats, seed: 8)
        var peerB = Race(track: track, players: seats, seed: 8)
        var watch = DivergenceWatch()

        for tick in 0..<200 {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in seats {
                inputs[seat] = CarInput(steer: sin(Double(tick) / 30), throttle: 1).quantised
            }
            peerA.advance(inputs: inputs)
            // Peer B's seat 1 gets a hair more throttle from tick 120 — the shape
            // a real desync takes: identical for a while, then quietly not.
            var theirInputs = inputs
            if tick >= 120 { theirInputs[seats[1]] = CarInput(steer: 0, throttle: 1) }
            peerB.advance(inputs: theirInputs)

            watch.record(tick: peerA.tick, hash: peerA.stateHash)
            watch.received(tick: peerB.tick, hash: peerB.stateHash, from: "b")
        }
        // Tick 121: the input at tick index 120 produces the state numbered 121.
        XCTAssertEqual(watch.firstDivergence?.tick, 121)
        XCTAssertNotEqual(watch.firstDivergence?.mine, watch.firstDivergence?.theirs)
    }

    func testIdenticalRacesNeverReportADivergence() {
        // The other half of the above, and the case a false positive would ruin:
        // two peers running the same inputs must stay silent for the whole race.
        let track = TrackLibrary.testRing()
        let seats = [PlayerID(0), PlayerID(1)]
        var peerA = Race(track: track, players: seats, seed: 8)
        var peerB = Race(track: track, players: seats, seed: 8)
        var watch = DivergenceWatch()
        for tick in 0..<400 {
            var inputs: [PlayerID: CarInput] = [:]
            for seat in seats {
                let aim = sin(Double(tick) / 50 + Double(seat.rawValue)) * .pi
                inputs[seat] = CarInput(throttle: 1, aim: aim).quantised
            }
            peerA.advance(inputs: inputs)
            peerB.advance(inputs: inputs)
            watch.record(tick: peerA.tick, hash: peerA.stateHash)
            watch.received(tick: peerB.tick, hash: peerB.stateHash, from: "b")
        }
        XCTAssertNil(watch.firstDivergence)
        XCTAssertEqual(watch.agreement(at: 400), true)
        XCTAssertEqual(watch.agreeingPeers, ["b"])
    }
}
