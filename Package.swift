// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hype",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .executable(name: "Hype", targets: ["Hype"]),
        .executable(name: "HypePacmanTestbedBuilder", targets: ["HypePacmanTestbedBuilder"]),
        .executable(name: "hypetalk", targets: ["HypeCLI"]),
        .library(name: "HypeCore", targets: ["HypeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
        // Vendored: upstream AudioKit's declared macOS minimum (10.13/11) no longer
        // compiles under current SDKs (auAudioUnit is macOS 13+). See
        // Vendor/AudioKit/HYPE_VENDOR_NOTE.md for provenance and the single patch.
        .package(path: "Vendor/AudioKit"),
    ],
    targets: [
        .executableTarget(
            name: "Hype",
            dependencies: ["HypeCore"],
            path: "Sources/Hype",
            exclude: ["SpriteKit/README.md"],
            resources: [
                .process("Resources/HypeDocIcon.icns"),
                .process("Resources/AppIcon.icns"),
                .process("Resources/OpenSourceManifest.json"),
            ]
        ),
        .executableTarget(
            name: "HypePacmanTestbedBuilder",
            dependencies: ["HypeCore"],
            path: "Sources/HypePacmanTestbedBuilder"
        ),
        .executableTarget(
            name: "HypeCLI",
            dependencies: [
                "HypeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/HypeCLI"
        ),
        .target(
            name: "HypeCore",
            dependencies: [
                "CStackImport",
                .product(name: "AudioKit", package: "AudioKit"),
            ],
            path: "Sources/HypeCore",
            resources: [
                .process("Resources/MeshyAnimationCatalog.json"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("c++"),
            ]
        ),
        .systemLibrary(
            name: "CStackImport",
            path: "Sources/CStackImport"
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
        .testTarget(
            name: "HypeCLITests",
            dependencies: ["HypeCore", "HypeCLI"],
            path: "Tests/HypeCLITests"
        ),
    ]
)
