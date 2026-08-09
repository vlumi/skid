import XCTest

@testable import SkidKit

/// **The one networking mistake that fails silently.**
///
/// If `NSBonjourServices` in Info.plist does not exactly match the service type
/// MultipeerConnectivity advertises, iOS 14+ refuses to browse and reports
/// nothing — it looks like "no peers nearby" rather than a misconfiguration. Two
/// devices cannot distinguish that from being out of range, so it is pinned here
/// where a mismatch is a red build instead of a wasted afternoon.
final class BonjourServiceTests: XCTestCase {
    /// Read from the repo rather than the bundle: these tests run headless via
    /// SwiftPM, where the iOS app's Info.plist is not loaded at all.
    private func infoPlist() throws -> [String: Any] {
        // …/Packages/SkidCore/Tests/SkidCoreTests/Sim/thisFile → repo root
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Sim
            .deletingLastPathComponent()  // SkidCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SkidCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
        let url = root.appendingPathComponent("Sources/iOS/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    func testBonjourServicesMatchTheAdvertisedServiceType() throws {
        let info = try infoPlist()
        let declared = try XCTUnwrap(
            info["NSBonjourServices"] as? [String],
            "NSBonjourServices is missing — iOS will refuse to browse, silently")

        // MultipeerConnectivity needs BOTH spellings: it uses TCP for reliable
        // sends and UDP for unreliable ones, and declaring only one half means
        // discovery works and then the race cannot send.
        let type = MultipeerTransport.serviceType
        XCTAssertTrue(
            declared.contains("_\(type)._tcp"), "missing _\(type)._tcp in NSBonjourServices")
        XCTAssertTrue(
            declared.contains("_\(type)._udp"), "missing _\(type)._udp in NSBonjourServices")
    }

    func testTheLocalNetworkPromptIsExplained() throws {
        let info = try infoPlist()
        let reason = try XCTUnwrap(
            info["NSLocalNetworkUsageDescription"] as? String,
            "without this the local-network prompt crashes the app on first browse")
        XCTAssertFalse(reason.isEmpty)
        // App Review rejects a bare "we need the network" — say what for.
        XCTAssertGreaterThan(reason.count, 30, "explain WHY, not just that")
    }

    func testTheServiceTypeIsLegal() {
        // Bonjour rules, and MC throws an exception on a bad one at runtime rather
        // than failing to compile: 1-15 characters, lowercase letters, digits and
        // hyphens only, no leading or trailing hyphen.
        let type = MultipeerTransport.serviceType
        XCTAssertFalse(type.isEmpty)
        XCTAssertLessThanOrEqual(type.count, 15, "MC rejects a service type over 15 characters")
        let legal = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        XCTAssertTrue(
            type.unicodeScalars.allSatisfy(legal.contains), "illegal character in \(type)")
        XCTAssertFalse(type.hasPrefix("-") || type.hasSuffix("-"), "hyphen at an end")
    }
}
