import XCTest

@testable import SkidCore

/// The aim knobs are FEEL knobs, and feel cannot be settled by arithmetic — so
/// every one of them has to be reachable from the tuning panel and take effect
/// live. These tests pin the behaviour each slider buys, so a knob that stops
/// being wired (or gets wired in the wrong unit) fails here.
///
/// The panel stores both angles in DEGREES because that is what the player is
/// reasoning about; the conversion lives at the apply site.
final class AimTuningTests: XCTestCase {
    private func source(forwardArc: Double, tailSwing: Double) -> AimControlSource {
        let source = AimControlSource()
        source.reverseThreshold = forwardArc * .pi / 180
        source.fullSteerError = tailSwing * .pi / 180
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        return source
    }

    /// Plant the thumb at `degrees` off the nose.
    ///
    /// The floating stick DRAGS its origin as the finger travels, so calling
    /// this twice from one touch does not deliver the second angle — asking for
    /// 130° after 180° actually yields 108°. Each call therefore re-plants the
    /// touch, and `knobDegrees` reports what the stick really delivered.
    private func aim(_ source: AimControlSource, degrees: Double) {
        source.releaseAll()
        source.touchBegan(id: TouchID(1), at: Vec2(500, 500))
        let radians = degrees * .pi / 180
        source.touchMoved(
            id: TouchID(1),
            at: Vec2(500 + cos(radians) * 80, 500 + sin(radians) * 80))
    }

    private func knobDegrees(_ source: AimControlSource) -> Double {
        atan2(source.knob.y, source.knob.x) * 180 / .pi
    }

    /// Widening the forward arc moves the boundary: a thumb at 130° is a
    /// forward chase under the stock 150° arc but a reverse under a 120° one.
    func testTheForwardArcMovesTheReverseBoundary() {
        for (arc, reverses) in [(150.0, false), (120.0, true)] {
            let source = source(forwardArc: arc, tailSwing: 45)
            aim(source, degrees: 130)
            source.setCar(heading: 0, forwardSpeed: 0, speed: 0)
            let input = source.input(for: PlayerID(0), at: Tick(0))
            XCTAssertEqual(
                input.aim == nil, reverses,
                "a 130° thumb with a \(arc)° forward arc")
        }
    }

    /// A tighter tail-swing lock reaches full steer sooner, so the tail comes
    /// around harder for the same thumb.
    func testTheTailSwingLockScalesTheSteer() {
        func steer(tailSwing: Double) -> Double {
            let source = source(forwardArc: 120, tailSwing: tailSwing)
            aim(source, degrees: 150)  // tail 30° off the thumb
            source.setCar(heading: 0, forwardSpeed: -50, speed: 50)
            return abs(source.input(for: PlayerID(0), at: Tick(0)).steer)
        }
        // 30° off the thumb: a 60° lock gives half steer, a 30° lock full.
        XCTAssertEqual(steer(tailSwing: 60), 0.5, accuracy: 0.01)
        XCTAssertEqual(steer(tailSwing: 30), 1.0, accuracy: 0.01)
        XCTAssertLessThan(
            steer(tailSwing: 120), steer(tailSwing: 60),
            "a looser lock must swing the tail more gently")
    }

    /// **"Reverse under" is a SPEED, not an angle.** The label read as an angle
    /// on device — and confusingly so, since the forward arc's own boundary is
    /// also 120. Raising it widens the speed window in which a behind-thumb
    /// reverses rather than flipping the body.
    func testReverseBelowSpeedIsASpeedWindow() {
        func reverses(atForwardSpeed speed: Double, below: Double) -> Bool {
            let source = source(forwardArc: 120, tailSwing: 60)
            source.reverseBelowSpeed = below
            aim(source, degrees: 180)
            source.setCar(heading: 0, forwardSpeed: speed, speed: abs(speed))
            return source.input(for: PlayerID(0), at: Tick(0)).aim == nil
        }
        XCTAssertFalse(reverses(atForwardSpeed: 100, below: 90), "100 > 90: flips")
        XCTAssertTrue(reverses(atForwardSpeed: 100, below: 120), "100 < 120: reverses")
        // And the signed-speed rule holds at any window: already reversing fast
        // is never "too fast to flip".
        XCTAssertTrue(reverses(atForwardSpeed: -300, below: 90))
    }

    /// **The release follows the arc.** A reverse already running survives
    /// until the aim comes `releaseMargin` INSIDE the forward arc — hysteresis,
    /// so the maneuver's own rotation can't chatter it on the boundary. Derived
    /// from the arc rather than absolute, so widening the arc doesn't leave a
    /// dead band where the reverse stays latched long past the boundary.
    func testTheReleaseFollowsTheForwardArc() {
        /// The delivered knob angle at which a running reverse lets go.
        func releaseAngle(forwardArc: Double) -> Double {
            let source = source(forwardArc: forwardArc, tailSwing: 60)
            // Commit to a reverse, straight back and slow enough to qualify.
            source.touchMoved(id: TouchID(1), at: Vec2(420, 500))
            source.setCar(heading: 0, forwardSpeed: -50, speed: 50)
            XCTAssertNil(source.input(for: PlayerID(0), at: Tick(0)).aim, "reversing")
            // Now drive FORWARD fast, so the speed arm cannot admit a fresh
            // reverse: from here only the latch's release band decides.
            source.setCar(heading: 0, forwardSpeed: 300, speed: 300)
            // Walk the finger around the origin. One planted touch, so the
            // origin drags — hence measuring what the stick delivers, not what
            // was asked for.
            var last = 180.0
            for step in stride(from: 179.0, through: -179.0, by: -1) {
                let radians = step * .pi / 180
                source.touchMoved(
                    id: TouchID(1),
                    at: Vec2(500 + cos(radians) * 200, 500 + sin(radians) * 200))
                let delivered = abs(knobDegrees(source))
                if source.input(for: PlayerID(0), at: Tick(1)).aim != nil { return last }
                last = delivered
            }
            return last
        }
        // Stock: hold to 30° inside a 120° arc, i.e. about 90°.
        XCTAssertEqual(releaseAngle(forwardArc: 120), 90, accuracy: 6)
        // Widen the arc and the release moves with it, rather than staying at 90.
        XCTAssertEqual(releaseAngle(forwardArc: 150), 120, accuracy: 6)
    }

    /// The stock values are the ones the behaviour tests assume, so a default
    /// change can't silently invalidate them.
    func testStockDefaults() {
        let source = AimControlSource()
        XCTAssertEqual(source.reverseThreshold, .pi * 5 / 6, accuracy: 1e-9, "150°")
        XCTAssertEqual(source.fullSteerError, .pi / 4, accuracy: 1e-9, "45°")
        XCTAssertEqual(source.reverseBelowSpeed, 90)
        XCTAssertEqual(source.releaseMargin, .pi / 6, accuracy: 1e-9, "30°")
    }
}
