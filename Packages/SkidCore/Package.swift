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
    ],
    targets: [
        .target(name: "SkidCore"),
        .target(
            name: "SkidKit",
            dependencies: ["SkidCore"],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "SkidCoreTests",
            dependencies: ["SkidCore"]
        ),
    ]
)
