// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeXCompanion",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "CompanionCore", targets: ["CompanionCore"]),
    ],
    targets: [
        .target(
            name: "CompanionCore",
            path: "Sources/CompanionCore"
        ),
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: ["CompanionCore"],
            path: "Tests/CompanionCoreTests"
        ),
        .executableTarget(
            name: "CompanionCoreCheck",
            dependencies: ["CompanionCore"],
            path: "Checks"
        ),
    ]
)
