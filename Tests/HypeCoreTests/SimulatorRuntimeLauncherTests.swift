import Foundation
import Testing
@testable import HypeCore

@Suite("Simulator runtime launcher")
struct SimulatorRuntimeLauncherTests {
    @Test("simctl JSON parser filters Apple runtime devices by Hype target")
    func parserFiltersAppleRuntimeDevicesByTarget() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              {
                "udid": "PHONE-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                "state": "Shutdown",
                "name": "iPhone 17"
              },
              {
                "udid": "PAD-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB",
                "state": "Booted",
                "name": "iPad Pro 13-inch (M5)"
              },
              {
                "udid": "UNAVAILABLE-1",
                "isAvailable": false,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
                "state": "Shutdown",
                "name": "iPhone 17 Pro"
              }
            ],
            "com.apple.CoreSimulator.SimRuntime.tvOS-26-5": [
              {
                "udid": "TV-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K",
                "state": "Shutdown",
                "name": "Apple TV 4K"
              }
            ],
            "com.apple.CoreSimulator.SimRuntime.watchOS-26-5": [
              {
                "udid": "WATCH-1",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm",
                "state": "Shutdown",
                "name": "Apple Watch"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let devices = try HypeSimulatorRuntimeLauncher.decodeAvailableDevices(from: json)

        #expect(devices.map(\.udid) == ["PHONE-1", "PAD-1", "TV-1"])
        #expect(devices.first { $0.udid == "PHONE-1" }?.platform == .iPhone)
        #expect(devices.first { $0.udid == "PAD-1" }?.platform == .iPad)
        #expect(devices.first { $0.udid == "TV-1" }?.platform == .tvOS)
        #expect(devices.first { $0.udid == "PAD-1" }?.runtimeName == "iOS 26.5")
    }

    @Test("launcher builds package and runs simulator commands without shell interpolation")
    func launcherRunsSimulatorCommandsWithoutShellInterpolation() async throws {
        var document = HypeDocument.newDocument(name: "Launch Test")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [.iPhone],
            primaryPlatform: .iPhone,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Tap Me"))

        let device = HypeSimulatorDevice(
            name: "iPhone 17",
            udid: "PHONE-1",
            platform: .iPhone,
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            runtimeName: "iOS 26.5",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            state: "Shutdown"
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeSimulatorLauncherTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let runner = RecordingSimulatorCommandRunner()
        let launcher = HypeSimulatorRuntimeLauncher(commandRunner: runner)
        let result = try await launcher.launch(
            document: document,
            platform: .iPhone,
            device: device,
            outputDirectory: output
        )
        let commands = await runner.recordedCommands()

        #expect(result.manifest.platform == .iPhone)
        #expect(result.manifest.runtimeOnly)
        #expect(result.manifest.bundleIdentifier == "com.hype.runtime.launch-test.iphone")
        #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
        #expect(commands.allSatisfy { $0.executableURL.path != "/bin/sh" })
        #expect(commands.contains { $0.executableURL.path == "/usr/bin/xcrun" && $0.arguments.prefix(2) == ["xcodebuild", "-project"] })
        #expect(commands.contains { $0.arguments.prefix(3) == ["simctl", "boot", "PHONE-1"] })
        #expect(commands.contains { $0.executableURL.path == "/usr/bin/open" && $0.arguments == ["-a", "Simulator", "--args", "-CurrentDeviceUDID", "PHONE-1"] })
        #expect(commands.contains { $0.arguments.prefix(3) == ["simctl", "install", "PHONE-1"] })
        #expect(commands.contains { $0.arguments == ["simctl", "launch", "PHONE-1", "com.hype.runtime.launch-test.iphone"] })
    }

    @Test(
        "live simulator smoke builds, installs, and launches a generated runtime app",
        .enabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_SIMULATOR_SMOKE"] == "1")
    )
    func liveSimulatorSmoke() async throws {
        let launcher = HypeSimulatorRuntimeLauncher()
        let devices = try await launcher.availableDevices()
        let device = HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPhone)
            ?? HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .iPad)
            ?? HypeSimulatorRuntimeLauncher.preferredDevice(from: devices, for: .tvOS)
        let selectedDevice = try #require(device)

        var document = HypeDocument.newDocument(name: "Live Simulator Smoke")
        document.stack.deploymentTargets = StackDeploymentTargets(
            selectedPlatforms: [selectedDevice.platform],
            primaryPlatform: selectedDevice.platform,
            selectionPromptAcknowledged: true,
            layoutPolicy: .scaleToFit
        )
        document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Smoke Button"))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypeLiveSimulatorSmoke-\(UUID().uuidString)", isDirectory: true)
        let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let result = try await launcher.launch(
            document: document,
            platform: selectedDevice.platform,
            device: selectedDevice,
            outputDirectory: output
        )

        #expect(result.manifest.runtimeOnly)
        #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
    }

    @Test(
        "live installed iPhone and iPad simulator matrix builds installs and launches generated runtime apps",
        .enabled(if: ProcessInfo.processInfo.environment["HYPE_LIVE_IOS_SIMULATOR_MATRIX"] == "1")
    )
    func liveInstalledIOSSimulatorMatrix() async throws {
        let launcher = HypeSimulatorRuntimeLauncher()
        let devices = try await launcher.availableDevices()
        let selectedDevices = devices
            .filter { $0.platform == .iPhone || $0.platform == .iPad }
            .filter { Self.currentShippingSimulatorNames.contains($0.name) }
        #expect(!selectedDevices.isEmpty)

        for device in selectedDevices {
            var document = HypeDocument.newDocument(name: "Simulator Matrix \(device.name)")
            document.stack.deploymentTargets = StackDeploymentTargets(
                selectedPlatforms: [device.platform],
                primaryPlatform: device.platform,
                selectionPromptAcknowledged: true,
                layoutPolicy: .scaleToFit
            )
            document.addPart(Part(partType: .button, cardId: document.cards[0].id, name: "Launch \(device.name)"))

            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("HypeSimulatorMatrix-\(device.udid)-\(UUID().uuidString)", isDirectory: true)
            let keepPackage = ProcessInfo.processInfo.environment["HYPE_KEEP_RUNTIME_TEST_PACKAGES"] == "1"
            defer {
                if !keepPackage {
                    try? FileManager.default.removeItem(at: output)
                }
            }

            let result = try await launcher.launch(
                document: document,
                platform: device.platform,
                device: device,
                outputDirectory: output
            )
            #expect(result.manifest.platform == device.platform)
            #expect(result.manifest.runtimeOnly)
            #expect(FileManager.default.fileExists(atPath: result.appBundleURL.path))
        }
    }

    private static let currentShippingSimulatorNames: Set<String> = [
        "iPhone 17 Pro",
        "iPhone 17 Pro Max",
        "iPhone Air",
        "iPhone 17",
        "iPhone 17e",
        "iPhone 16",
        "iPhone 16 Plus",
        "iPad Pro 13-inch (M5)",
        "iPad Pro 11-inch (M5)",
        "iPad Air 13-inch (M4)",
        "iPad Air 11-inch (M4)",
        "iPad (A16)",
        "iPad mini (A17 Pro)",
    ]
}

private actor RecordingSimulatorCommandRunner: HypeSimulatorCommandRunning {
    private var commands: [HypeSimulatorCommand] = []

    func run(_ command: HypeSimulatorCommand) async throws -> HypeSimulatorCommandResult {
        commands.append(command)
        if command.executableURL.path == "/usr/bin/xcrun",
           command.arguments.first == "xcodebuild" {
            try createFakeBuildProduct(for: command)
        }
        return HypeSimulatorCommandResult(
            command: command,
            terminationStatus: 0,
            outputData: Data()
        )
    }

    func recordedCommands() -> [HypeSimulatorCommand] {
        commands
    }

    private func createFakeBuildProduct(for command: HypeSimulatorCommand) throws {
        let arguments = command.arguments
        guard let scheme = value(after: "-scheme", in: arguments),
              let derivedDataPath = value(after: "-derivedDataPath", in: arguments),
              let sdk = value(after: "-sdk", in: arguments) else { return }
        let productDirectory = sdk == "appletvsimulator" ? "Debug-appletvsimulator" : "Debug-iphonesimulator"
        let appURL = URL(fileURLWithPath: derivedDataPath)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent(productDirectory, isDirectory: true)
            .appendingPathComponent("\(scheme).app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}
