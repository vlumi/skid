import XCTest

@testable import SkidCore
@testable import SkidKit

/// **"Reset to defaults" has to mean every dial on the panel.**
///
/// The failure this guards is a quiet one: `resetPhysics` covers exactly the dials
/// `isStockPhysics` reads (a rule the hiscores depend on), so for a while the panel's
/// reset left the aim shape, the d-pad feel, the elevation and the pace exactly as
/// tuned — a restore that restored half the panel.
///
/// `resetAllTunings` repeats the stock literals, because `@AppStorage` keeps them in the
/// property declarations where nothing can read them back. Repeated literals drift, so
/// these compare against the values a *cleared* store produces rather than against more
/// literals.
@MainActor
final class GameSettingsResetTests: XCTestCase {
    /// Every dial the panel shows, as a name and a way to read it. `debugOverlay` is a
    /// Bool and rides separately.
    private static let dials: [ReferenceWritableKeyPath<GameSettings, Double>] = [
        \.aimTurnRate, \.aimFlipBoost, \.steerFlipBoost, \.driftRetention,
        \.turnRate, \.gripScale, \.speedGripFade, \.wallRestitution, \.wallGlanceBounce,
        \.wallFriction, \.wallDragFloor, \.gravity, \.wallYaw,
        \.pace, \.dpadSteerAtFullThrottle,
        \.dpadSteerTravel, \.dpadSteerRecentring,
        \.dpadRecentringSpeed, \.dpadFullThrottle, \.dpadCoast,
        \.aimReverseBelowSpeed, \.aimThrottleEase, \.aimForwardArcDegrees,
        \.aimTailSwingDegrees, \.deckScale,
    ]

    /// Wipe every `skid.` key so the properties fall back to their declared defaults.
    private func clearStore() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("skid.") {
            defaults.removeObject(forKey: key)
        }
    }

    override func setUp() {
        super.setUp()
        clearStore()
    }

    override func tearDown() {
        clearStore()
        super.tearDown()
    }

    /// **A reset lands on the factory values**, dial for dial.
    ///
    /// The factory values are read from a settings object over a cleared store — so a
    /// literal in `resetAllTunings` that drifts away from its property declaration fails
    /// here, which is the whole reason this is written this way.
    func testResetLandsOnTheDeclaredDefaults() {
        // Read over the CLEARED store, before anything is tuned — `@AppStorage` is
        // backed by `UserDefaults.standard`, so every instance shares one store and a
        // "fresh" object made after tuning would report the tuned values.
        let settings = GameSettings()
        let factory = Self.dials.map { settings[keyPath: $0] }
        let factoryOverlay = settings.debugOverlay

        // Move every dial somewhere it is not.
        settings.aimTurnRate += 1
        settings.aimFlipBoost += 1
        settings.steerFlipBoost += 1
        settings.driftRetention -= 0.3
        settings.turnRate += 1
        settings.gripScale += 0.5
        settings.wallRestitution += 0.2
        settings.wallGlanceBounce += 0.2
        settings.wallFriction += 0.01
        settings.wallDragFloor += 0.2
        settings.gravity += 2
        settings.wallYaw += 0.01
        settings.pace = 0.5
        settings.dpadSteerTravel += 10
        settings.dpadSteerRecentring += 0.5
        settings.dpadRecentringSpeed -= 0.3
        settings.dpadSteerAtFullThrottle += 0.2
        settings.dpadCoast += 0.1
        settings.dpadFullThrottle += 0.1
        settings.aimReverseBelowSpeed += 20
        settings.aimThrottleEase += 0.2
        settings.aimForwardArcDegrees += 20
        settings.aimTailSwingDegrees += 10
        settings.deckScale += 0.2
        settings.debugOverlay = true

        settings.resetAllTunings()

        for (index, dial) in Self.dials.enumerated() {
            XCTAssertEqual(
                settings[keyPath: dial], factory[index], accuracy: 1e-9,
                "a dial did not come back to its factory value (index \(index))")
        }
        XCTAssertEqual(settings.debugOverlay, factoryOverlay)
    }

    /// **It covers strictly more than the physics reset**, which is the gap that prompted
    /// it: `resetPhysics` leaves the d-pad, the aim shape, the elevation and the pace.
    func testItResetsWhatThePhysicsResetLeavesBehind() {
        let settings = GameSettings()
        settings.dpadSteerTravel += 20
        settings.aimForwardArcDegrees += 30
        settings.deckScale += 0.2
        settings.pace = 0.5

        settings.resetPhysics()
        // 55 = the tuned value. Compared against the literal, not another `GameSettings`:
        // every instance shares `UserDefaults.standard`, so a "fresh" one reads the tuned
        // value too — which is what made the first version of this test fail.
        XCTAssertEqual(settings.dpadSteerTravel, 55.0, accuracy: 1e-9, "physics reset left it")

        settings.resetAllTunings()
        XCTAssertEqual(settings.dpadSteerTravel, 35.0, accuracy: 1e-9)
        XCTAssertEqual(settings.aimForwardArcDegrees, 150.0, accuracy: 1e-9)
        XCTAssertEqual(settings.deckScale, 1.2, accuracy: 1e-9)
        XCTAssertEqual(settings.pace, 1.0, accuracy: 1e-9)
    }

    /// A reset leaves the car stock, so records can be set again.
    func testAResetIsStockEnoughToRecord() {
        let settings = GameSettings()
        settings.gripScale += 0.6
        XCTAssertFalse(settings.isStockPhysics)
        settings.resetAllTunings()
        XCTAssertTrue(settings.isStockPhysics)
    }

    /// The elevation knob is a renderer global, so a reset has to push it — otherwise the
    /// slider says 1.2 and the decks stay where they were.
    func testResettingPushesTheElevationGlobal() {
        let settings = GameSettings()
        settings.deckScale = 1.55
        settings.applyRenderTuning()
        XCTAssertEqual(Elevation.deckScale, 1.55, accuracy: 1e-9)
        settings.resetAllTunings()
        XCTAssertEqual(Elevation.deckScale, 1.2, accuracy: 1e-9)
    }
}
