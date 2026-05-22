// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hype",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Hype", targets: ["Hype"]),
        .executable(name: "HypePacmanTestbedBuilder", targets: ["HypePacmanTestbedBuilder"]),
        .library(name: "HypeCore", targets: ["HypeCore"]),
    ],
    targets: [
        .executableTarget(
            name: "Hype",
            dependencies: ["HypeCore"],
            path: "Sources/Hype"
        ),
        .executableTarget(
            name: "HypePacmanTestbedBuilder",
            dependencies: ["HypeCore"],
            path: "Sources/HypePacmanTestbedBuilder"
        ),
        .target(
            name: "HypeCore",
            path: "Sources/HypeCore",
            resources: [
                .process("Resources/MeshyAnimationCatalog.json"),
            ]
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
