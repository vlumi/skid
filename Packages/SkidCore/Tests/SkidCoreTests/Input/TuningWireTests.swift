import XCTest

@testable import SkidCore
@testable import SkidKit

/// The wall knobs must actually REACH the sim. Five sliders that look right and
/// change nothing would be worse than none — and the panel had none at all until
/// the maintainer asked whether they were in the tuning UI.
@MainActor
final class TuningWireTests: XCTestCase {
    /// `@AppStorage` is real UserDefaults, shared across the whole test run — so a
    /// test that moves a knob leaves it moved for every later one. Reset to stock.
    private func stockSettings() -> GameSettings {
        let settings = GameSettings()
        let stock = CarTuning()
        settings.wallRestitution = stock.wallRestitution
        settings.wallGlanceBounce = stock.wallGlanceBounce
        settings.wallFriction = stock.wallFriction
        settings.wallDragFloor = stock.wallDragFloor
        settings.wallYaw = stock.wallYaw
        settings.gravity = stock.gravity
        settings.launchPerSpeed = stock.launchPerSpeed
        return settings
    }

    func testTheWallKnobsReachCarTuning() {
        let settings = stockSettings()
        settings.wallRestitution = 0.11
        settings.wallGlanceBounce = 0.22
        settings.wallFriction = 0.033
        settings.wallDragFloor = 0.44
        settings.wallYaw = 0.055
        // Pace scales speeds, not these, so they should arrive untouched.
        settings.pace = 1.0

        let tuning = settings.carTuning
        XCTAssertEqual(tuning.wallRestitution, 0.11, accuracy: 1e-9)
        XCTAssertEqual(tuning.wallGlanceBounce, 0.22, accuracy: 1e-9)
        XCTAssertEqual(tuning.wallFriction, 0.033, accuracy: 1e-9)
        XCTAssertEqual(tuning.wallDragFloor, 0.44, accuracy: 1e-9)
        XCTAssertEqual(tuning.wallYaw, 0.055, accuracy: 1e-9)
    }

    /// The air knobs too — flight feel is the point of them, so they have to be
    /// tunable on device rather than only in source.
    func testTheAirKnobsReachCarTuning() {
        let settings = stockSettings()
        settings.gravity = 27
        settings.launchPerSpeed = 0.007
        settings.pace = 1.0

        let tuning = settings.carTuning
        XCTAssertEqual(tuning.gravity, 27, accuracy: 1e-9)
        XCTAssertEqual(tuning.launchPerSpeed, 0.007, accuracy: 1e-9)
    }

    /// A moved air knob is non-stock as well: it changes lap times, so a
    /// hiscore set with it would not be comparable.
    func testAMovedAirKnobIsNotStockPhysics() {
        let settings = stockSettings()
        XCTAssertTrue(settings.isStockPhysics)
        settings.gravity = 30
        XCTAssertFalse(settings.isStockPhysics, "gravity changes how long a fall costs")

        let other = stockSettings()
        // DERIVED from stock, not a literal: this was `0.008`, which silently became
        // the stock default when the jump's gap grew to a road width — so the test
        // was asserting that the default is not the default.
        other.launchPerSpeed = CarTuning().launchPerSpeed * 2
        XCTAssertFalse(other.isStockPhysics, "so does how far a jump goes")
    }

    /// And a moved wall knob counts as non-stock, so hiscores stay honest.
    func testAMovedWallKnobIsNotStockPhysics() {
        let settings = stockSettings()
        XCTAssertTrue(settings.isStockPhysics, "defaults should read as stock")
        settings.wallFriction = 0.04
        XCTAssertFalse(
            settings.isStockPhysics,
            "a tuned wall changes lap times, so it must not count as stock")
    }
}
