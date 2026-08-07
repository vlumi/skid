// swift-tools-version:5.9
import Foundation
import PackageDescription

// **Experimental features are opt-in**, and not tied to the DEBUG configuration:
// an ordinary debug build is what gets driven while testing everything else, so
// half-finished chrome must stay out of it unless asked for.
//
//     SKID_EXPERIMENTAL=1 swift build
//     SKID_EXPERIMENTAL=1 make project     (for the Xcode app target)
//
// See docs/experimental-features.md. The Xcode side sets the same condition via
// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in project.yml.
let experimental = ProcessInfo.processInfo.environment["SKID_EXPERIMENTAL"] == "1"
let experimentalSettings: [SwiftSetting] =
    experimental ? [.define("SKID_EXPERIMENTAL")] : []

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
            swiftSettings: experimentalSettings
        ),
        .executableTarget(
            name: "SkidIcon",
            dependencies: ["SkidKit"]
        ),
        .testTarget(
            name: "SkidCoreTests",
            dependencies: ["SkidCore", "SkidKit"],
            swiftSettings: experimentalSettings
        ),
    ]
)
