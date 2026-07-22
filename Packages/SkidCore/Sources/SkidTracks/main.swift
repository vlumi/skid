// Dev tool for the bundled track designs. Run via `make tracks-lint` /
// `make tracks-export`:
//
//   skid-tracks lint            validate every bundled design
//   skid-tracks export <dir>    write every design + the manifest to <dir>,
//                               canonically encoded (the migration vehicle,
//                               and the re-encoder for format bumps)

import Foundation
import SkidCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "lint" {
case "lint":
    var clean = true
    for design in TrackLibrary.designs {
        let issues = design.validationIssues()
        if issues.isEmpty {
            print("✓ \(design.id)")
        } else {
            clean = false
            for issue in issues {
                print("✗ \(design.id): \(issue)")
            }
        }
    }
    if !clean { exit(1) }

case "export":
    guard arguments.count > 2 else { fail("usage: skid-tracks export <dir>") }
    let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    do {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        for design in TrackLibrary.designs {
            let url = directory.appendingPathComponent("\(design.id).json")
            try TrackDesignFile(design: design).encoded().write(to: url)
            print("wrote \(url.path)")
        }
        let manifest = TrackManifest(tracks: TrackLibrary.designs.map(\.id))
        let manifestURL = directory.appendingPathComponent("manifest.json")
        try manifest.encoded().write(to: manifestURL)
        print("wrote \(manifestURL.path)")
    } catch {
        fail("export failed: \(error)")
    }

default:
    fail("unknown subcommand '\(arguments[1])' — expected lint|export")
}
