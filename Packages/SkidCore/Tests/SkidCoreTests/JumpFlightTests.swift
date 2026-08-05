import Foundation
import Testing

@testable import SkidCore

/// **Clearing a jump is earned.** The launch kick scales with speed, so distance
/// is quadratic in it. These drive the real sim over a real compiled jump.
///
/// Driven by the **AI**, not a bare `throttle: 1`: a jump sits partway around a
/// ring, and a car with no steering just leaves the road at the first corner —
/// an early version of these tests "proved" the car never flew for exactly that
/// reason, having never reached the jump at all.
struct JumpFlightTests {
    private struct Flight {
        var flew = false
        var lowestHeight = Double.greatestFiniteMagnitude
        /// The highest the car got ABOVE the road it launched from. This, not
        /// `flew`, is what separates being thrown from merely falling in — a car
        /// dropping into the gap is `isAirborne` too.
        var riseAboveLip = 0.0
        var wallImpacts = 0
        var reachedTheGap = false
    }

    /// Drive one AI lap and report what happened at the gap. `pace` scales the
    /// car's speed caps, which is how a slow approach is arranged honestly rather
    /// than by fighting the AI's throttle.
    private func lap(_ track: Track, pace: Double = 1.0, ticks: Int = 60 * Race.tickRate)
        -> Flight
    {
        var race = Race(
            track: track, players: [PlayerID(0)], tuning: CarTuning().scaled(pace: pace),
            config: RaceConfig(laps: 1))
        var driver = AIDriver()
        var flight = Flight()
        let gapPoints = track.centerline.indices.filter { track.segmentIsGap($0) }
        // The deck the jump sits on, so a RISE can be told from a fall.
        let lipHeight = gapPoints.first.map { track.height(ofPoint: $0) } ?? 0
        for _ in 0..<ticks {
            race.advance(inputs: [PlayerID(0): driver.input(car: race.cars[0].state, track: track)])
            let car = race.cars[0].state
            if car.isAirborne { flight.flew = true }
            flight.riseAboveLip = max(flight.riseAboveLip, car.height - lipHeight)
            for event in race.lastEvents {
                if case .wallImpact = event { flight.wallImpacts += 1 }
            }
            // Near the gap in 2D, whatever the car's height.
            if let nearest = gapPoints.min(by: {
                car.position.distance(to: track.centerline[$0])
                    < car.position.distance(to: track.centerline[$1])
            }), car.position.distance(to: track.centerline[nearest]) < Double(PieceCatalog.width) {
                flight.reachedTheGap = true
                flight.lowestHeight = min(flight.lowestHeight, car.height)
            }
            if race.cars[0].progress.finishedAt != nil { break }
        }
        return flight
    }

    /// The gap is crossable: a car arriving at speed is **thrown UP** off the lip.
    ///
    /// Asserted on the rise, not on `isAirborne`: a car falling into the gap is
    /// airborne too, so an `isAirborne` check passed even with the launch kick
    /// deleted outright. The rise is the only witness that a launch happened.
    @Test func aCarAtSpeedLaunchesOffTheLip() {
        let flight = lap(TestTracks.jumpRing())
        #expect(flight.reachedTheGap, "the AI never got to the jump — fixture or lap problem")
        #expect(flight.flew, "the launch lip never threw the car")
        #expect(
            flight.riseAboveLip > 0.05,
            "the car never rose above the lip (\(flight.riseAboveLip)) — it fell in, not flew")
    }

    /// A jump must not be a wall: nothing emitted across the gap may stop a car
    /// mid-flight. This is what the rail suppression buys.
    @Test func nothingBlocksTheFlightCorridor() {
        let flight = lap(TestTracks.jumpRing())
        #expect(flight.wallImpacts == 0, "car hit \(flight.wallImpacts) wall(s) crossing the jump")
    }

    /// **A jump at height falls to what is BENEATH it, not to its own level.**
    /// The elevated ring jumps at height 1 over open ground, so a car that fails
    /// to clear ends up a full storey down.
    @Test func fallingOffAnElevatedJumpLandsOnTheGroundBelow() {
        // A quarter-pace car cannot carry enough speed off the lip to clear it.
        let flight = lap(TestTracks.elevatedJumpRing(), pace: 0.25)
        #expect(flight.reachedTheGap, "the AI never got to the elevated jump")
        #expect(
            flight.lowestHeight < 1 - Track.reachTolerance,
            "a car that fell into an elevated gap stayed up at \(flight.lowestHeight)")
    }

    /// **Clearing the gap is EARNED**: the same jump, cleared at racing speed and
    /// missed at a crawl. This is the property the whole feature exists for, and
    /// it is what a mis-sized gap breaks in either direction — too wide and no
    /// speed clears it, too narrow and no speed misses.
    /// Measured on the ELEVATED ring, because height is the only honest witness:
    /// on a ground-level jump both outcomes bottom out at 0 — there is nowhere
    /// below the grass to fall — so the ground ring cannot tell them apart.
    @Test func speedDecidesWhetherTheGapIsCleared() {
        let track = TestTracks.elevatedJumpRing()
        let fast = lap(track)
        let slow = lap(track, pace: 0.25)
        #expect(fast.reachedTheGap && slow.reachedTheGap, "the AI never got to the jump")
        #expect(
            fast.lowestHeight > 1 - Track.reachTolerance,
            "a full-speed car should stay up at deck height, dipped to \(fast.lowestHeight)")
        #expect(
            slow.lowestHeight < Track.reachTolerance,
            "a crawling car should fall to the ground, got \(slow.lowestHeight)")
        // And the kick itself scales with speed — a FIXED kick would launch the
        // crawler just as hard, which is the "quadratic vs linear" distinction the
        // tuning exists to preserve.
        #expect(
            slow.riseAboveLip < fast.riseAboveLip,
            "the launch kick ignored speed: slow \(slow.riseAboveLip) vs fast \(fast.riseAboveLip)")
    }

    /// The elevated jump ring must be lappable at all — a jump on a deck is a
    /// legal track, not a trap that ends the race.
    @Test func anElevatedJumpRingIsLappable() {
        let track = TestTracks.elevatedJumpRing()
        var race = Race(track: track, players: [PlayerID(0)], config: RaceConfig(laps: 1))
        var driver = AIDriver()
        var ticks = 0
        while race.cars[0].progress.finishedAt == nil, ticks < 120 * Race.tickRate {
            race.advance(inputs: [PlayerID(0): driver.input(car: race.cars[0].state, track: track)])
            ticks += 1
        }
        #expect(
            race.cars[0].progress.finishedAt != nil,
            "AI never lapped the elevated jump ring (gate \(race.cars[0].progress.nextGate))")
    }
}
