// swift-tools-version:5.9
import PackageDescription

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
        // Dev tool: validates + canonicalizes the bundled track designs.
        .executable(name: "skid-tracks", targets: ["SkidTracks"]),
    ],
    targets: [
        .target(
            name: "SkidCore",
            resources: [.copy("Resources/Tracks")]
        ),
        .target(
            name: "SkidKit",
            dependencies: ["SkidCore"],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .executableTarget(
            name: "SkidIcon",
            dependencies: ["SkidKit"]
        ),
        .executableTarget(
            name: "SkidTracks",
            dependencies: ["SkidCore"]
        ),
        .testTarget(
            name: "SkidCoreTests",
            dependencies: ["SkidCore"]
        ),
    ]
)
