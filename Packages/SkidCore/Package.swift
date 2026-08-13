// swift-tools-version:5.9
import Foundation
import PackageDescription

// **One flag per feature**, because they are wanted in different places. Lumping
// them together meant a build could not have the tuning dials without also getting
// half-finished editor chrome.
//
// See docs/experimental-features.md. The Xcode side sets the same conditions via
// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in project.yml.

// **Experimental features are opt-IN**, and not tied to the DEBUG configuration:
// an ordinary debug build is what gets driven while testing everything else, so
// half-finished chrome must stay out of it unless asked for.
//
//     SKID_EXPERIMENTAL=1 swift build
//     SKID_EXPERIMENTAL=1 make project     (for the Xcode app target)
let experimental = ProcessInfo.processInfo.environment["SKID_EXPERIMENTAL"] == "1"

// **The tuning dials are opt-OUT — present unless explicitly removed.**
//
// Deliberately the opposite default from `SKID_EXPERIMENTAL`, because the dials are
// wanted in exactly the builds that flag excludes: **TestFlight builds are release
// builds**, and tuning on a real device is what they are for. Gating them as
// "experimental" would have removed them from every build that matters and left them
// only in local ones.
//
// Turned off for the eventual production release, where a developer tool has no
// business shipping:
//
//     SKID_NO_TUNING=1 swift build
//     SKID_NO_TUNING=1 make project
let tuning = ProcessInfo.processInfo.environment["SKID_NO_TUNING"] != "1"

let featureFlagSettings: [SwiftSetting] =
    (experimental ? [.define("SKID_EXPERIMENTAL")] : [])
    + (tuning ? [.define("SKID_TUNING")] : [])

let package = Package(
    name: "SkidCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        // Pure simulation — deterministic, no UI dependencies. Headlessly testable.
        .library(name: "SkidCore", targets: ["SkidCore"]),
        // SwiftUI rendering + input glue. Depends on SkidCore.
        .library(name: "SkidKit", targets: ["SkidKit"]),
        // Dev tool: renders the app icon from the game's own drawing code.
        .executable(name: "skid-icon", targets: ["SkidIcon"]),
    ],
    targets: [
        .target(name: "SkidCore"),
        .target(
            name: "SkidKit",
            dependencies: ["SkidCore"],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: featureFlagSettings
        ),
        .executableTarget(
            name: "SkidIcon",
            dependencies: ["SkidKit"]
        ),
        .testTarget(
            name: "SkidCoreTests",
            dependencies: ["SkidCore", "SkidKit"],
            swiftSettings: featureFlagSettings
        ),
    ]
)
