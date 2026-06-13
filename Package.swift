// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hype",
    // watchOS is declared so the HypeTalk interpreter kernel (Script/ + the
    // Foundation-only Models/provider subset) can be built for watch by a
    // consumer. AudioKit is excluded on watch via a per-platform dependency
    // condition below — the kernel itself has no watch-incompatible API once
    // AppleMusicProvider's ApplicationMusicPlayer path is guarded out.
    platforms: [.macOS(.v15), .iOS(.v17), .tvOS(.v16), .watchOS(.v10)],
    products: [
        .executable(name: "Hype", targets: ["Hype"]),
        .executable(name: "HypePacmanTestbedBuilder", targets: ["HypePacmanTestbedBuilder"]),
        .executable(name: "hypetalk", targets: ["HypeCLI"]),
        .library(name: "HypeCore", targets: ["HypeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
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
                // AudioKit is unavailable on watchOS (its vendored package
                // declares no .watchOS platform). Gate the dependency to the
                // platforms where it exists so the package still resolves for a
                // watch build of the interpreter kernel.
                .product(
                    name: "AudioKit",
                    package: "AudioKit",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS])
                ),
            ],
            path: "Sources/HypeCore",
            resources: [
                .process("Resources/MeshyAnimationCatalog.json"),
            ],
            swiftSettings: [
                // Optimize for size in release builds. HypeCore is the shippable
                // library destined for mobile/watch; the interpreter is large but
                // not the per-instruction hottest code (the hot loops are small),
                // so -Osize trades a few percent CPU for a large __text reduction.
                // Measured: Interpreter.o __text 1.56 MB -> 824 KB (~48% smaller),
                // for a ~2-13% median pure-CPU cost on the realistic suite (the
                // cost lands on a pure-CPU path that production frame-pacing masks).
                // Gated to release so debug builds keep -Onone (fast incremental).
                .unsafeFlags(["-Osize"], .when(configuration: .release)),
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
