import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Two devices with the same name.** Reported from device: two phones both
/// called "iPhone" collided as one peer, so the guest's join was refused as
/// `alreadyJoined`, both screens showed a single device, both believed they were
/// the host, and Start stayed disabled with no explanation.
///
/// The roster was never at fault — it correctly refuses a duplicate. The bug was
/// keying device identity on a name that is not unique, and swallowing the refusal
/// with `try?`.
final class PeerIdentityTests: XCTestCase {
    func testTwoDevicesWithTheSameNameGetDistinctKeys() {
        // The fix, stated directly: whatever the devices are called, two launches
        // must not produce the same key.
        let keys = (0..<50).map { _ in DeviceName.uniqueKey() }
        XCTAssertEqual(Set(keys).count, keys.count, "peer keys collided")
    }

    func testTheFriendlyNameSurvivesForDisplay() {
        // A bare UUID would be unreadable in a lobby, so the key has to carry the
        // human part — and `display` has to recover exactly it.
        let key = DeviceName.uniqueKey()
        XCTAssertEqual(DeviceName.display(key), DeviceName.friendly)
        XCTAssertNotEqual(key, DeviceName.friendly, "the key is not unique at all")
        XCTAssertTrue(key.hasPrefix(DeviceName.friendly.prefix(4)))
    }

    func testDisplayFallsBackForAKeyWithoutASuffix() {
        // A peer from an older build sends a bare name; it must still read sensibly
        // rather than showing blank.
        XCTAssertEqual(DeviceName.display("iPhone"), "iPhone")
        XCTAssertEqual(DeviceName.display(""), "")
        // A pathological key that is only a suffix falls back to the whole string
        // rather than rendering as nothing.
        XCTAssertEqual(DeviceName.display("#abcd"), "#abcd")
    }

    func testAKeyFitsMultipeerConnectivitysLimit() {
        // MC truncates a display name past 63 bytes SILENTLY, which would chop the
        // suffix off and reintroduce the collision this exists to prevent.
        XCTAssertLessThanOrEqual(DeviceName.uniqueKey().utf8.count, 63)

        // **With a name long enough to hit the clamp** — this machine's device
        // name is short, so `uniqueKey()` alone cannot reach the limit and the
        // assertion above passes whatever the clamp does.
        let long = String(repeating: "Ville's very long iPhone name ", count: 5)
        let key = DeviceName.key(for: long)
        XCTAssertLessThanOrEqual(key.utf8.count, 63, "MC will truncate and drop the suffix")
        // The suffix must survive the trim — it is the part that makes it unique.
        XCTAssertTrue(key.contains(DeviceName.separator))
        XCTAssertEqual(key.split(separator: DeviceName.separator).last?.count, 4)
        // And two long-named devices still differ.
        XCTAssertNotEqual(DeviceName.key(for: long), DeviceName.key(for: long))
    }

    func testTwoDistinctKeysBothSeatSuccessfully() {
        // The end-to-end shape of the device failure: with distinct keys, both
        // devices are seated, seat numbers do not overlap, and exactly one of them
        // is the host.
        var roster = RaceRoster()
        let hostKey = DeviceName.uniqueKey()
        let guestKey = DeviceName.uniqueKey()
        XCTAssertNotEqual(hostKey, guestKey)

        let hostSeats = try? roster.join(hostKey, seats: 2)
        let guestSeats = try? roster.join(guestKey, seats: 2)
        XCTAssertEqual(hostSeats?.count, 2)
        XCTAssertEqual(guestSeats?.count, 2, "the guest was refused, as on device")
        XCTAssertEqual(Set(hostSeats ?? []).intersection(Set(guestSeats ?? [])), [])
        XCTAssertEqual(roster.entries.count, 2, "the lobby would show one device")
        // Exactly one host — the guest believing it was the host is what disabled
        // Start on both screens.
        XCTAssertEqual(roster.host, hostKey)
        XCTAssertNotEqual(roster.host, guestKey)
    }

    func testIdenticalKeysReproduceTheDeviceFailure() {
        // The bug itself, pinned so the shape of it stays understood: identical
        // keys mean one entry, and the guest reads as the host.
        var roster = RaceRoster()
        XCTAssertNoThrow(try roster.join("iPhone", seats: 2))
        XCTAssertThrowsError(try roster.join("iPhone", seats: 2)) { error in
            XCTAssertEqual(error as? RaceRoster.JoinError, .alreadyJoined("iPhone"))
        }
        XCTAssertEqual(roster.entries.count, 1)
        XCTAssertEqual(roster.host, "iPhone", "both devices would compute isHost == true")
    }
}
