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
    func testTurningTheStripOffRestoresTheFloatingPad() {
        let p = pad()
        p.cruiseStrip = 0
        p.touchBegan(id: 1, at: Vec2(90, 90))
        p.touchMoved(id: 1, at: Vec2(90, 90 - p.radius))  // straight "up"
        XCTAssertGreaterThan(input(p).throttle, 0.9)
        p.touchMoved(id: 1, at: Vec2(90 + p.radius, 90))  // sideways
        let side = input(p)
        XCTAssertGreaterThan(side.steer, 0.9)
        XCTAssertEqual(side.throttle, 0, accuracy: 1e-9)
    }
}
