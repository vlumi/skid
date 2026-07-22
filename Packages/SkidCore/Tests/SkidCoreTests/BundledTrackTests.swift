import XCTest

@testable import SkidCore

/// The bundled track JSON is the source of truth — these keep it honest.
final class BundledTrackTests: XCTestCase {
    func testManifestAndRosterAgree() {
        XCTAssertEqual(
            TrackLibrary.designs.map(\.id),
            ["practice-loop", "gauntlet", "hairpin", "overpass"])
        XCTAssertEqual(TrackLibrary.all.map(\.id), TrackLibrary.designs.map(\.id))
    }

    func testEveryBundledDesignIsValid() {
        for design in TrackLibrary.designs {
            XCTAssertTrue(
                design.validationIssues().isEmpty,
                "\(design.id): \(design.validationIssues())")
        }
    }

    func testBundledFilesAreCanonicallyEncoded() throws {
        // Re-encoding a bundled file must be byte-identical — catches
        // hand edits that drift from the canonical encoder (fix by
        // rerunning `make tracks-export`).
        for design in TrackLibrary.designs {
            let data = try XCTUnwrap(TrackLibrary.bundledData(resource: design.id))
            let file = try XCTUnwrap(TrackDesignFile.decode(data))
            XCTAssertEqual(file.version, TrackDesignFile.currentVersion)
            XCTAssertEqual(try file.encoded(), data, "\(design.id) is not canonical")
        }
        let manifestData = try XCTUnwrap(TrackLibrary.bundledData(resource: "manifest"))
        let manifest = try XCTUnwrap(TrackManifest.decode(manifestData))
        XCTAssertEqual(try manifest.encoded(), manifestData, "manifest is not canonical")
    }
}
