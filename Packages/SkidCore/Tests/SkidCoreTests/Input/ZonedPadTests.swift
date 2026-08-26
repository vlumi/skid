import Foundation
import XCTest

@testable import SkidCore

/// **The Pro pad — one model, chosen by device-play elimination.**
///
/// Mouse-style steering (movement winds the wheel, stillness recentres it,
/// speed-weighted) over one continuous gas axis (full throttle at the top,
/// coast at `coastDepth`, full reverse at the bottom). The eliminated
/// designs — floating pad, from-entry anchor, cruise strip, brake band —
/// each died on a device; their lessons live in the survivor's contract,
/// which is what these pin. Numbers stay dials, not decisions.
final class ZonedPadTests: XCTestCase {
    /// An SE's 4-player zone, the tightest case the model must work in.
    private let zone = Rect(x: 0, y: 0, width: 187, height: 183)

    private func pad() -> VirtualDPadControlSource {
        let source = VirtualDPadControlSource()
        source.bounds = zone
        source.steerTravel = 60
        source.steerRecentring = 1.2
        // Zero so recentring is exactly the dial; the speed test dials it up.
        source.recentringSpeedWeight = 0
        source.steerAtFullThrottle = 0.5
        source.fullThrottleDepth = 0.3
        source.coastDepth = 0.6
        return source
    }

    /// A point at a given depth down the zone (0 = top) and column.
    private func at(depth: Double, x: Double) -> Vec2 {
        Vec2(x, zone.origin.y + depth * zone.size.y)
    }

    private func input(_ p: VirtualDPadControlSource, _ tick: Tick = 0) -> CarInput {
        p.input(for: PlayerID(0), at: tick)
    }

    // MARK: - Steering

    /// **Moving the thumb turns.** 30 points of a 60-point travel is half a
    /// lock, wherever in the zone the movement happens — position never
    /// matters, so there is no centre to lose.
    func testMovementWindsTheWheel() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.6, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        XCTAssertEqual(input(p).steer, 0.5, accuracy: 1e-9)
    }

    /// **Stillness straightens, exactly.** A residue of a few thousandths is
    /// the invisible steer the whole rework exists to kill.
    func testAStillThumbRecentres() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.6, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        XCTAssertEqual(input(p, 0).steer, 0.5, accuracy: 1e-9)
        // 0.1 s at 1.2 locks/s unwinds 0.12.
        XCTAssertEqual(input(p, 6).steer, 0.38, accuracy: 1e-9)
        XCTAssertEqual(input(p, 66).steer, 0, accuracy: 1e-12)
    }

    /// The same tick sampled twice — the sim and then the render — must not
    /// recentre twice.
    func testASecondReadOfTheSameTickDoesNotRecentreAgain() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.6, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        _ = input(p, 0)
        let first = input(p, 6).steer
        XCTAssertEqual(input(p, 6).steer, first, accuracy: 1e-12)
    }

    /// **Recentring rides the car's speed.** At full weight a parked car
    /// keeps its lock forever — a slow off-road recovery must not fight the
    /// wheel — and a flat-out car sheds it at the full rate.
    func testRecentringScalesWithCarSpeed() {
        let slow = pad()
        slow.recentringSpeedWeight = 1
        slow.setCar(heading: 0, forwardSpeed: 0, speed: 0)
        slow.touchBegan(id: 1, at: at(depth: 0.6, x: 60))
        slow.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        _ = input(slow, 0)
        XCTAssertEqual(input(slow, 60).steer, 0.5, accuracy: 1e-9, "a parked car recentred")

        let fast = pad()
        fast.recentringSpeedWeight = 1
        fast.setCar(heading: 0, forwardSpeed: fast.fullSpeed, speed: fast.fullSpeed)
        fast.touchBegan(id: 1, at: at(depth: 0.6, x: 60))
        fast.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        _ = input(fast, 0)
        XCTAssertLessThan(abs(input(fast, 60).steer), 0.01, "a flat-out car kept its lock")
    }

    /// **Lifting straightens.** A wheel that survived into a new touch would
    /// be held lock nothing on the screen accounts for.
    func testANewTouchStartsStraight() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.6, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 120))
        p.touchEnded(id: 1)
        p.touchBegan(id: 2, at: at(depth: 0.6, x: 60))
        XCTAssertEqual(input(p, 1).steer, 0, accuracy: 1e-12)
    }

    // MARK: - The gas axis

    /// **One continuous axis with a full-gas plateau**: pinned at 1 down to
    /// `fullThrottleDepth` (holding flat-out must not mean pinning the finger
    /// to the box's edge), ramping to coast, then into reverse at the very
    /// bottom. The sim itself turns negative throttle into braking while
    /// rolling and reverse once stopped.
    func testDepthIsOneContinuousGasAxis() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0, x: 90))
        XCTAssertEqual(input(p).throttle, 1, accuracy: 1e-9, "top is not full gas")
        p.touchMoved(id: 1, at: at(depth: 0.29, x: 90))
        XCTAssertEqual(input(p).throttle, 1, accuracy: 1e-9, "the plateau is not full gas")
        p.touchMoved(id: 1, at: at(depth: 0.45, x: 90))
        XCTAssertEqual(input(p).throttle, 0.5, accuracy: 1e-9, "mid-ramp is not half gas")
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        XCTAssertEqual(input(p).throttle, 0, accuracy: 1e-9, "the coast point is not neutral")
        p.touchMoved(id: 1, at: at(depth: 0.8, x: 90))
        XCTAssertEqual(input(p).throttle, -0.5, accuracy: 1e-9, "below coast is not braking")
        p.touchMoved(id: 1, at: at(depth: 1.0, x: 90))
        XCTAssertEqual(input(p).throttle, -1, accuracy: 1e-9, "the bottom is not full reverse")
    }

    /// **Gas + grip**: at full throttle only `steerAtFullThrottle` of the
    /// wheel survives; at the coast point it all does; in reverse the wheel
    /// has full bite — backing out of a pinch needs it.
    func testThrottleTradesAgainstSteering() {
        func steer(atDepth depth: Double) -> Double {
            let p = pad()
            p.touchBegan(id: 1, at: at(depth: depth, x: 60))
            p.touchMoved(id: 1, at: at(depth: depth, x: 120))  // a full lock's travel
            return input(p).steer
        }
        XCTAssertEqual(steer(atDepth: 0), 0.5, accuracy: 1e-9, "full gas did not soften the wheel")
        XCTAssertEqual(
            steer(atDepth: 0.29), 0.5, accuracy: 1e-9,
            "the plateau's steering should match full gas — it IS full gas")
        XCTAssertEqual(steer(atDepth: 0.6), 1.0, accuracy: 1e-9, "coasting did not restore it")
        XCTAssertEqual(steer(atDepth: 0.9), 1.0, accuracy: 1e-9, "reversing lost the wheel")
    }

    // MARK: - The visible line

    /// **The neutral line IS the wheel, seen**: half a lock leaves it half a
    /// travel behind the thumb, and a still thumb watches it come back
    /// underneath. Only the sideways component means anything — the line is
    /// full-height, so its returned point rides at the thumb.
    func testTheNeutralLineTrailsAndCatchesUp() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.6, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        guard let base = p.stickBase, let thumb = p.touchPoint else {
            return XCTFail("no line to draw")
        }
        XCTAssertEqual(base.x, 60, accuracy: 1e-9, "half a lock is half a travel behind")
        XCTAssertEqual(base.y, thumb.y, accuracy: 1e-9)
        _ = input(p, 0)
        _ = input(p, 66)
        XCTAssertEqual(p.stickBase?.x ?? -1, 90, accuracy: 1e-9, "the line never caught up")
    }
}
