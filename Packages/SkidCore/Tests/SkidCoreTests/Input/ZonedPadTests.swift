import Foundation
import XCTest

@testable import SkidCore

/// **The zone-strip pad**, the third attempt at Pro controls.
///
/// The reported problem: a floating pad's centre is a point on glass with
/// nothing to feel for, so after a corner you hold a little lock you cannot
/// detect and sail down the lane in a slow sine curve. A longer travel made it
/// worse (more space to hunt in) and a self-centring wheel did not cure it
/// (a resting thumb keeps asking for its own position). This model gives the
/// thumb an EDGE instead of a point.
///
/// These pin the contract, not the feel — the numbers are being chosen by
/// driving, and the tuning panel exposes them for exactly that reason.
final class ZonedPadTests: XCTestCase {
    /// An SE's 4-player zone, which is the tightest case the model must work in.
    private let zone = Rect(x: 0, y: 0, width: 187, height: 183)

    private func pad(_ meaning: VirtualDPadControlSource.DepthMeaning = .steerOnly)
        -> VirtualDPadControlSource
    {
        let source = VirtualDPadControlSource()
        source.bounds = zone
        source.cruiseStrip = 0.3
        source.brakeBand = 0.25
        source.depthMeaning = meaning
        source.levels = nil
        source.expo = 1
        // These tests pin the from-entry model; followMovement has its own
        // fixture below.
        source.steerModel = .fromEntry
        return source
    }

    /// The mouse-style pad: sideways MOVEMENT winds the wheel, stillness lets
    /// it recentre. Speed weight zeroed so the rate is exactly the dial.
    private func movementPad() -> VirtualDPadControlSource {
        let source = pad()
        source.steerModel = .followMovement
        source.steerTravel = 60
        source.steerRecentring = 1.2
        source.recentringSpeedWeight = 0
        return source
    }

    /// A point at a given depth down the zone (0 = top) and column.
    private func at(depth: Double, x: Double) -> Vec2 {
        Vec2(x, zone.origin.y + depth * zone.size.y)
    }

    private func input(_ p: VirtualDPadControlSource, _ tick: Tick = 0) -> CarInput {
        p.input(for: PlayerID(0), at: tick)
    }

    // MARK: - The cruise strip

    /// **Full throttle, no steering, anywhere along the strip.** This is what
    /// makes it a place to reposition: sliding sideways up here does nothing to
    /// the car, so the thumb can be put wherever it wants to be.
    func testTheStripIsFullThrottleAndNeutralWhereverYouSlide() {
        let p = pad()
        for x in [20.0, 90.0, 160.0] {
            p.touchBegan(id: 1, at: at(depth: 0.1, x: 90))
            p.touchMoved(id: 1, at: at(depth: 0.1, x: x))
            let out = input(p)
            XCTAssertEqual(out.throttle, 1, accuracy: 1e-9, "not full gas at x=\(x)")
            XCTAssertEqual(out.steer, 0, accuracy: 1e-9, "the strip steered at x=\(x)")
            p.touchEnded(id: 1)
        }
    }

    // MARK: - Steering below it

    /// **Straight-ahead is wherever you crossed the edge**, so hand position
    /// never matters — only movement away from it.
    func testSteeringIsMeasuredFromWhereTheThumbLeftTheStrip() {
        for entry in [40.0, 90.0, 150.0] {
            let p = pad()
            p.touchBegan(id: 1, at: at(depth: 0.1, x: entry))
            // Drop straight down out of the strip: no sideways movement yet.
            p.touchMoved(id: 1, at: at(depth: 0.6, x: entry))
            XCTAssertEqual(
                input(p).steer, 0, accuracy: 1e-9,
                "entering at x=\(entry) was not straight-ahead")
            // Now move right: that is a right turn, from wherever we entered.
            p.touchMoved(id: 1, at: at(depth: 0.6, x: entry + 40))
            XCTAssertGreaterThan(input(p).steer, 0, "moving right did not steer right")
        }
    }

    /// Returning to the strip **resets** the reference, which is the whole point
    /// of having somewhere to reposition to.
    func testGoingBackIntoTheStripResetsStraightAhead() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.1, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 60))
        _ = input(p)
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 130))  // a big right turn
        XCTAssertGreaterThan(input(p).steer, 0.3)
        // Back up into the strip, slide, and come down again.
        p.touchMoved(id: 1, at: at(depth: 0.1, x: 130))
        XCTAssertEqual(input(p).steer, 0, accuracy: 1e-9)
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 130))
        XCTAssertEqual(
            input(p).steer, 0, accuracy: 1e-9,
            "the reference did not reset — the old sine curve is back")
    }

    /// **Faded in**, so a thumb wobbling across the edge does not snap the wheel.
    func testSteeringFadesInBelowTheEdge() {
        let p = pad()
        p.steerFadeDepth = 24
        p.touchBegan(id: 1, at: at(depth: 0.1, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.31, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.31, x: 120))  // hard right, just below
        _ = input(p)
        let justBelow = abs(input(p).steer)
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 120))  // same offset, deeper
        let deeper = abs(input(p).steer)
        XCTAssertLessThan(justBelow, deeper, "steering did not fade in")
    }

    // MARK: - Follow movement

    /// **Moving the thumb turns.** 30 points of a 60-point travel is half
    /// lock, wherever in the band the movement happens.
    func testMovementWindsTheWheel() {
        let p = movementPad()
        p.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        XCTAssertEqual(input(p).steer, 0.5, accuracy: 1e-9)
    }

    /// **Stillness straightens.** A held thumb adds nothing, so the wheel
    /// unwinds at the dialled rate — and reaches exactly zero, because a
    /// residue of a few thousandths is the invisible steer this whole rework
    /// exists to kill.
    func testAStillThumbRecentres() {
        let p = movementPad()
        p.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        XCTAssertEqual(input(p, 0).steer, 0.5, accuracy: 1e-9)
        // 0.1 s at 1.2 locks/s unwinds 0.12.
        XCTAssertEqual(input(p, 6).steer, 0.38, accuracy: 1e-9)
        // And a second is more than enough to finish the job, exactly.
        XCTAssertEqual(input(p, 66).steer, 0, accuracy: 1e-12)
    }

    /// The same tick sampled twice — the sim and then the render — must not
    /// recentre twice, or the wheel would unwind at whatever frame rate the
    /// busiest caller has.
    func testASecondReadOfTheSameTickDoesNotRecentreAgain() {
        let p = movementPad()
        p.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        _ = input(p, 0)
        let first = input(p, 6).steer
        XCTAssertEqual(input(p, 6).steer, first, accuracy: 1e-12)
    }

    /// **Recentring can ride the car's speed.** At weight 1 a parked car keeps
    /// its lock forever and a flat-out car sheds it at the full rate — the
    /// self-aligning-torque analogy, and the dial the user asked for.
    func testRecentringScalesWithCarSpeed() {
        let slow = movementPad()
        slow.recentringSpeedWeight = 1
        slow.setCar(heading: 0, forwardSpeed: 0, speed: 0)
        slow.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        slow.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        _ = input(slow, 0)
        XCTAssertEqual(input(slow, 60).steer, 0.5, accuracy: 1e-9, "a parked car recentred")

        let fast = movementPad()
        fast.recentringSpeedWeight = 1
        fast.setCar(heading: 0, forwardSpeed: fast.fullSpeed, speed: fast.fullSpeed)
        fast.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        fast.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        _ = input(fast, 0)
        XCTAssertLessThan(
            abs(input(fast, 60).steer), 0.01, "a flat-out car kept its lock")
    }

    /// **The strip is an instant straighten.** Sliding up into it drops the
    /// wheel at once — the panic move — and coming back down starts from zero.
    func testSlidingIntoTheStripDropsTheWheelAtOnce() {
        let p = movementPad()
        p.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 120))
        XCTAssertGreaterThan(abs(input(p, 0).steer), 0.5)
        p.touchMoved(id: 1, at: at(depth: 0.1, x: 120))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 120))
        XCTAssertEqual(input(p, 1).steer, 0, accuracy: 1e-12)
    }

    /// **Lifting straightens.** A wheel that survived the lift would be held
    /// lock nothing on the screen accounts for.
    func testLiftingDropsTheWheel() {
        let p = movementPad()
        p.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 120))
        p.touchEnded(id: 1)
        p.touchBegan(id: 2, at: at(depth: 0.5, x: 60))
        XCTAssertEqual(input(p, 1).steer, 0, accuracy: 1e-12)
    }

    // MARK: - The visible joystick

    /// **The base IS the wheel, seen.** Winding half a lock leaves the base
    /// half a travel behind the thumb, level with it.
    func testTheBaseTrailsTheWheel() {
        let p = movementPad()
        p.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        guard let base = p.stickBase, let thumb = p.touchPoint else {
            return XCTFail("no stick to draw")
        }
        XCTAssertEqual(base.x, 60, accuracy: 1e-9, "half a lock is half a travel behind")
        XCTAssertEqual(base.y, thumb.y, accuracy: 1e-9)
    }

    /// **A still thumb watches the base slide back underneath it** — the
    /// recentring, made visible where the thumb actually is.
    func testTheBaseCatchesUpToAStillThumb() {
        let p = movementPad()
        p.touchBegan(id: 1, at: at(depth: 0.5, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        _ = input(p, 0)
        _ = input(p, 66)  // more than enough at 1.2 locks/s
        XCTAssertEqual(p.stickBase?.x ?? -1, 90, accuracy: 1e-9, "the base never caught up")
    }

    /// **Vertically the base is towed, never recentred.** Depth in the zone
    /// means throttle, so there is no vertical home to return to — the base
    /// just stays within a travel of the thumb, like the floating stick's rim.
    func testTheBaseIsTowedVerticallyAndStaysPut() {
        let p = movementPad()
        p.touchBegan(id: 1, at: Vec2(90, 64))
        p.touchMoved(id: 1, at: Vec2(90, 164))  // 100 down: towed the last 40
        XCTAssertEqual(p.stickBase?.y ?? -1, 104, accuracy: 1e-9, "not towed to a travel behind")
        _ = input(p, 0)
        _ = input(p, 120)  // two seconds of stillness
        XCTAssertEqual(p.stickBase?.y ?? -1, 104, accuracy: 1e-9, "the base recentred vertically")
        p.touchMoved(id: 1, at: Vec2(90, 80))  // back up, within reach: no tow
        XCTAssertEqual(p.stickBase?.y ?? -1, 104, accuracy: 1e-9)
    }

    /// Under from-entry steering the base sits at the anchor — the same
    /// drawing tells that model's story too.
    func testFromEntryBaseSitsAtTheAnchor() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.1, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.5, x: 120))
        XCTAssertEqual(p.stickBase?.x ?? -1, 90, accuracy: 1e-9, "the base left the anchor")
    }

    // MARK: - Throttle

    /// Steer-only: the gas stays pinned while steering, so a drift can be held.
    func testSteerOnlyKeepsTheGasPinned() {
        let p = pad(.steerOnly)
        p.touchBegan(id: 1, at: at(depth: 0.1, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.6, x: 150))
        let out = input(p)
        XCTAssertEqual(out.throttle, 1, accuracy: 1e-9, "steering cost throttle")
        XCTAssertGreaterThan(abs(out.steer), 0.1)
    }

    /// **Gas + grip: deeper eases the gas and firms the steering.** One
    /// relationship rather than two controls — pinned is fast and straight,
    /// lifting lets the wheel bite.
    func testGasAndGripTradesThrottleForSteering() {
        let p = pad(.gasAndGrip)
        p.touchBegan(id: 1, at: at(depth: 0.1, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.35, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.35, x: 150))
        let shallow = input(p)
        p.touchMoved(id: 1, at: at(depth: 0.7, x: 150))
        let deep = input(p)
        XCTAssertGreaterThan(shallow.throttle, deep.throttle, "depth did not ease the gas")
        XCTAssertGreaterThan(
            abs(deep.steer), abs(shallow.steer), "lifting did not firm the steering")
    }

    /// **At full gas the wheel pulls all the way to straight**, not merely
    /// toward it — a residue of a few thousandths would be the same
    /// undetectable steer that started this whole rework, just smaller.
    func testGasAndGripSnapsASmallSteerToStraight() {
        let p = pad(.gasAndGrip)
        p.throttleRecentring = 2.0
        p.touchBegan(id: 1, at: at(depth: 0.1, x: 90))
        // Just below the strip: full throttle, so the recentring is strongest —
        // and a tiny sideways nudge, so it has something to pull to zero.
        p.touchMoved(id: 1, at: at(depth: 0.305, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.305, x: 91))
        let out = input(p)
        XCTAssertEqual(out.steer, 0, accuracy: 1e-12, "a nudge at full gas did not straighten")
        XCTAssertGreaterThan(out.throttle, 0.9, "fixture: should still be near full gas")
    }

    /// Braking is the bottom band, and reverse reaches full at the very bottom
    /// — it only has to get you out of a pinch.
    func testTheBottomBandBrakesAndReverses() {
        let p = pad()
        p.touchBegan(id: 1, at: at(depth: 0.1, x: 90))
        p.touchMoved(id: 1, at: at(depth: 0.99, x: 90))
        XCTAssertLessThan(input(p).throttle, -0.9, "the bottom of the zone did not reverse")
    }

    /// With the strip off, the pad is the old floating one — so the previous
    /// model stays reachable while the new one is being judged on device.
    /// **No strip is the default now**, and it must still be the ZONED pad:
    /// steering live right up to the top edge, the brake band at the bottom,
    /// the joystick drawn. Turning the strip off used to fall back to the old
    /// floating pad; the recentring made the strip's job redundant and the
    /// zoned pad is the only pad a zone gets.
    func testNoStripSteersFromTheTopAndStillBrakes() {
        let p = movementPad()
        p.cruiseStrip = 0
        p.touchBegan(id: 1, at: at(depth: 0.05, x: 60))
        p.touchMoved(id: 1, at: at(depth: 0.05, x: 90))  // near the very top
        let out = input(p)
        XCTAssertEqual(out.steer, 0.5, accuracy: 0.2, "no steering near the top edge")
        XCTAssertEqual(out.throttle, 1, accuracy: 1e-9)
        XCTAssertNotNil(p.stickBase, "the joystick vanished with the strip")
        p.touchMoved(id: 1, at: at(depth: 0.99, x: 90))
        XCTAssertLessThan(input(p).throttle, -0.8, "the brake band went with the strip")
    }
}
