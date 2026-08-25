import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The panel's dials actually reach the pad.** The settings and the control
/// source are separate objects joined only by `applyControlTuning`; a dial that
/// never gets wired shows in the panel, saves to the store, and changes
/// nothing — which is exactly how a tuning session stops meaning anything.
/// Nothing pinned this route before; the steer-model round adds enough dials
/// that a silent miss became likely.
@MainActor
final class ControlTuningWiringTests: XCTestCase {
    /// Wipe every `skid.` key so this test neither reads a previous run's
    /// dials nor leaks its own — the same trap the setup file hit with
    /// process-wide UserDefaults.
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

    func testEveryProLayoutDialReachesThePad() {
        let game = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "wiring-test-tracks.json",
            profileFilename: "wiring-test-profiles.json",
            hiscoreFilename: "wiring-test-hiscores.json",
            setupFilename: "wiring-test-setup.json")
        game.rig = CouchRig(colorIndices: [0])

        // Off-default on every dial, so a missed wire cannot pass by luck.
        game.settings.dpadCruiseStrip = 0.4
        game.settings.dpadBrakeBand = 0.2
        game.settings.dpadDepthMeaning =
            VirtualDPadControlSource.DepthMeaning.gasAndGrip.rawValue
        game.settings.dpadSteerAtFullThrottle = 0.5
        game.settings.dpadThrottleRecentring = 3.0
        game.settings.dpadSteerModel =
            VirtualDPadControlSource.SteerModel.fromEntry.rawValue
        game.settings.dpadSteerTravel = 80
        game.settings.dpadSteerRecentring = 2.5
        game.settings.dpadRecentringSpeed = 0.75

        game.applyControlTuning()

        guard let pad = game.rig?.players.first?.pro else {
            return XCTFail("no rig player to read back")
        }
        XCTAssertEqual(pad.cruiseStrip, 0.4)
        XCTAssertEqual(pad.brakeBand, 0.2)
        XCTAssertEqual(pad.depthMeaning, .gasAndGrip)
        XCTAssertEqual(pad.steerAtFullThrottle, 0.5)
        XCTAssertEqual(pad.throttleRecentring, 3.0)
        XCTAssertEqual(pad.steerModel, .fromEntry)
        XCTAssertEqual(pad.steerTravel, 80)
        XCTAssertEqual(pad.steerRecentring, 2.5)
        XCTAssertEqual(pad.recentringSpeedWeight, 0.75)
        // fullSpeed rides the car tuning, pace folded in.
        XCTAssertEqual(pad.fullSpeed, game.settings.carTuning.maxSpeed)
    }
}
