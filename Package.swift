// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hype",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Hype", targets: ["Hype"]),
        .library(name: "HypeCore", targets: ["HypeCore"]),
    ],
    targets: [
        .executableTarget(
            name: "Hype",
            dependencies: ["HypeCore"],
            path: "Sources/Hype"
        ),
        .target(
            name: "HypeCore",
            path: "Sources/HypeCore"
        ),
        .testTarget(
            name: "HypeCoreTests",
            dependencies: ["HypeCore"],
            path: "Tests/HypeCoreTests"
        ),
        .testTarget(
            name: "HypeTests",
            dependencies: ["Hype", "HypeCore"],
            path: "Tests/HypeTests"
        ),
    ]
)
